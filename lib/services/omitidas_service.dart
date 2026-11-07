import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/registro_toma.dart';
import '../models/tratamiento.dart';
import '../utils/hash_estable.dart';
import '../utils/vigencia_tratamiento.dart';
import 'alerta_sin_tomas_service.dart';
import 'firestore_service.dart';
import 'notificaciones_service.dart';
import 'push_service.dart';

/// Una toma programada concreta: la ranura lógica de una dosis.
///
/// La identidad de una ranura es `(tratamientoId, horaProgramada)`. No alcanza
/// el `tratamientoId` solo (un tratamiento tiene varias tomas al día) ni la hora
/// sola (varios medicamentos pueden coincidir). `horaProgramada` es el
/// `DateTime` local de pared con fecha completa y `HH:mm`, que es exactamente
/// lo que ya se persiste como `Timestamp` en cada registro.
class RanuraToma {
  final String tratamientoId;
  final DateTime horaProgramada;

  const RanuraToma({required this.tratamientoId, required this.horaProgramada});

  /// Clave estable y comparable de la ranura. Usa el instante en milisegundos
  /// (no `toString()`) porque es lo que realmente se guarda en Firestore.
  String get clave => '$tratamientoId|${horaProgramada.millisecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is RanuraToma &&
      other.tratamientoId == tratamientoId &&
      other.horaProgramada == horaProgramada;

  @override
  int get hashCode => clave.hashCode;

  @override
  String toString() => 'RanuraToma($clave)';
}

/// Una toma que acaba de marcarse como olvidada en una pasada de reconciliación.
///
/// `OmitidasService.reconciliar` la devuelve **solo cuando el registro se
/// escribió en esta pasada**: la idempotencia (id determinista + `resueltas`)
/// garantiza que una toma ya olvidada no reaparezca, y así el aviso al cuidador
/// no se duplica por cada tick de 60s.
class OmitidaNueva {
  final String tratamientoId;
  final String nombreMedicamento;
  final DateTime horaProgramada;

  const OmitidaNueva({
    required this.tratamientoId,
    required this.nombreMedicamento,
    required this.horaProgramada,
  });

  /// Hora local "HH:mm" para el cuerpo de la notificación.
  String get horaTxt {
    final h = horaProgramada.hour.toString().padLeft(2, '0');
    final m = horaProgramada.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Marca automáticamente las tomas que el paciente dejó pasar sin confirmar.
///
/// Sin servidor (no hay Cloud Functions ni FCM) el cliente es la única fuente de
/// verdad, así que la detección es **reactiva y retrospectiva**: no hay nada que
/// registre una toma perdida en el momento en que se pierde. Lo que hace esta
/// clase es, cada vez que la app está viva, comparar las tomas que deberían
/// haber ocurrido con las que tienen algún registro, y escribir "olvidada" para
/// las que no.
///
/// Regla implementada: una toma queda como olvidada cuando **llega la hora del
/// siguiente medicamento programado** (de cualquier tratamiento del paciente) y
/// esa toma anterior no tiene ningún registro en estado terminal. Es la regla
/// literal, sin excepciones.
///
/// Dos consecuencias deliberadas de esa regla:
///
///  - La última toma del día NO vence sola: queda esperando a que llegue la
///    primera del día siguiente. Si la app no se abre, el backfill lo resuelve
///    igual cuando vuelva a abrirse (la ventana avanza y aparece el siguiente).
///  - Una toma pospuesta ("Recordar") que nunca se confirma también acaba en
///    olvidada, porque `pospuesta` no es un estado terminal. Coherente con el
///    criterio que ya usaba el chequeo de alarma.
///
/// Lo que NO puede hacer (limitación del modelo sin backend): si el paciente
/// nunca abre la app, no se registra nada. El cuidador ve la ausencia de un
/// registro, que no distingue "no confirmó" de "la app estuvo apagada".
class OmitidasService {
  final FirestoreService _fs = FirestoreService();
  final NotificacionesService _notif = NotificacionesService();
  final PushService _push = PushService();

  /// Avisos de "5 días sin tomas" ya enviados en esta sesión, para que la
  /// caché de tratamientos (que puede tardar hasta 5 min en refrescarse) no
  /// provoque un segundo FCM el mismo día.
  final Map<String, DateTime> _avisosSinTomasEnviados = <String, DateTime>{};

  /// Evita que dos reconciliaciones solapadas envíen el mismo aviso a la vez.
  final Set<String> _avisosSinTomasEnCurso = <String>{};

  DateTime? _ultimaEvaluacionAlertas;
  String? _firmaTratamientosAlertas;

  /// Cuántos días hacia atrás se revisan al reconciliar.
  ///
  /// Acota el backfill: sin tope, la primera apertura tras una ausencia larga
  /// dispararía tantas escrituras como tomas hubiera en semanas. 7 días es
  /// suficiente para cubrir el uso real (el paciente casi siempre vuelve en
  /// menos de una semana) y mantiene el peor caso acotado.
  static const int ventanaDias = 7;

  /// Cuánto se conserva en memoria la lista de tratamientos para el atajo de la
  /// ruta rápida. Pasado este plazo se vuelve a leer de Firestore, para que un
  /// horario editado por el cuidador no tarde indefinidamente en reflejarse.
  static const Duration vigenciaCacheTratamientos = Duration(minutes: 5);

  List<Tratamiento>? _tratamientosCache;
  DateTime? _cacheLeida;

  /// Firma del último conjunto de tomas vencidas ya reconciliado.
  String? _firma;

  /// Estados de tratamientos finalizados cuyas notificaciones ya se cancelaron
  /// en esta sesión. La clave incluye fecha/duración/horarios para que, si el
  /// cuidador reactiva y vuelve a finalizar el tratamiento, se cancele de nuevo.
  final Set<String> _finalizadosCancelados = <String>{};

  /// Ranuras de un día concreto según los horarios de cada tratamiento.
  ///
  /// El filtro por día de la semana es lo que impide inventar falsamente: un
  /// horario `dias: [1,3,5]` no genera nada en un martes. `DateTime.weekday` ya
  /// es ISO (1=lunes … 7=domingo), la misma convención de `HorarioDia.dias`, así
  /// que no hace falta conversión.
  ///
  /// Deduplica por clave porque dos entradas con la misma hora y días que se
  /// solapan (el editor de tratamientos lo permite) describirían la misma ranura
  /// dos veces.
  static List<RanuraToma> ranurasDelDia(
    List<Tratamiento> tratamientos,
    DateTime dia,
  ) {
    final resultado = <RanuraToma>[];
    final vistas = <String>{};

    for (final t in tratamientos) {
      // Fuera de la fecha de inicio/fin no existen ranuras: ni tomas pendientes
      // ni, por tanto, "olvidadas" posteriores al último día.
      if (!VigenciaTratamiento.estaVigente(t, dia)) continue;
      for (final h in t.horarios) {
        if (!h.dias.contains(dia.weekday)) continue;
        final hh = h.hora.split(':');
        if (hh.length != 2) continue;
        final hora = int.tryParse(hh[0]);
        final minuto = int.tryParse(hh[1]);
        if (hora == null || minuto == null) continue;
        if (hora > 23 || minuto > 59) continue;

        final ranura = RanuraToma(
          tratamientoId: t.id,
          horaProgramada: DateTime(dia.year, dia.month, dia.day, hora, minuto),
        );
        if (vistas.add(ranura.clave)) resultado.add(ranura);
      }
    }
    return resultado;
  }

  /// Ranuras que deberían marcarse como olvidadas, ordenadas cronológicamente.
  ///
  /// Una ranura está vencida cuando existe otra ranura **estrictamente
  /// posterior** (de cualquier tratamiento) cuya hora ya llegó. Se exige que sea
  /// estrictamente posterior porque dos medicamentos a la misma hora no pueden
  /// marcarse mutuamente: si lo hicieran, una toma de las 08:00 quedaría
  /// "olvidada" en el instante exacto en que vencía.
  ///
  /// [diasAtras] cuenta días hacia atrás desde hoy, hoy incluido.
  static List<RanuraToma> ranurasVencidas({
    required List<Tratamiento> tratamientos,
    required DateTime ahora,
    int diasAtras = ventanaDias,
  }) {
    if (diasAtras < 1) return const [];

    final inicioHoy = DateTime(ahora.year, ahora.month, ahora.day);
    final todas = <RanuraToma>[];
    for (var d = diasAtras - 1; d >= 0; d--) {
      todas.addAll(
        ranurasDelDia(tratamientos, inicioHoy.subtract(Duration(days: d))),
      );
    }

    todas.sort((a, b) => a.horaProgramada.compareTo(b.horaProgramada));
    final unicas = <RanuraToma>[];
    final vistas = <String>{};
    for (final r in todas) {
      if (vistas.add(r.clave)) unicas.add(r);
    }

    final vencidas = <RanuraToma>[];
    for (var i = 0; i < unicas.length; i++) {
      // La siguiente estrictamente posterior, saltando las que caen a la misma
      // hora (otro medicamento a la misma hora no es "la siguiente").
      var siguiente = -1;
      for (var j = i + 1; j < unicas.length; j++) {
        if (unicas[j].horaProgramada.isAfter(unicas[i].horaProgramada)) {
          siguiente = j;
          break;
        }
      }
      // Sin siguiente no hay por qué vencer: la última toma del período queda
      // esperando a que aparezca una posterior.
      if (siguiente < 0) continue;
      if (!unicas[siguiente].horaProgramada.isAfter(ahora)) {
        vencidas.add(unicas[i]);
      }
    }
    return vencidas;
  }

  /// Claves de las ranuras que ya están resueltas.
  ///
  /// Solo cuentan los estados terminales (`tomó`, `tardó`, `olvidada`). Una
  /// toma con un único registro `pospuesta` sigue sin resolverse y por eso sí
  /// genera una olvidada.
  static Set<String> clavesResueltas(List<RegistroToma> registros) {
    final resueltas = <String>{};
    for (final r in registros) {
      if (!r.estado.esTerminal) continue;
      resueltas.add(
        '${r.tratamientoId}|${r.horaProgramada.millisecondsSinceEpoch}',
      );
    }
    return resueltas;
  }

  /// Id de documento determinista para la toma olvidada de una ranura.
  ///
  /// Es la barrera de idempotencia de verdad: en vez de dejar que Firestore
  /// genere un id, dos reconciliaciones solapadas (un tick que pisa a otro, o
  /// un `resumed` junto al tick) escriben el MISMO documento en lugar de crear
  /// dos. Así la protección no depende de evitar el solapamiento, que no se
  /// puede garantizar, sino de que el solapamiento sea inofensivo.
  static String idDocumento(String tratamientoId, DateTime horaProgramada) {
    final ranura = RanuraToma(
      tratamientoId: tratamientoId,
      horaProgramada: horaProgramada,
    );
    return hashEstable('omitida|${ranura.clave}').toString();
  }

  /// Firma del conjunto de tomas vencidas, para detectar cambios sin releer.
  static String firmaDe(List<RanuraToma> vencidas) =>
      vencidas.map((r) => r.clave).join('|');

  /// Reconcilia, marca las tomas olvidadas y evalúa la alerta de 5 días sin
  /// tomas. Devuelve las olvidadas que acaba de escribir; el aviso al cuidador
  /// se maneja dentro de este método.
  ///
  /// Ruta rápida: si el conjunto de tomas vencidas no cambió desde la última
  /// vez y no hay una alerta pendiente que revisar, no se toca Firestore en
  /// absoluto (ni lectura ni escritura). Es lo que hace aceptable un tick
  /// periódico. La lista de tratamientos se reutiliza en
  /// memoria hasta [vigenciaCacheTratamientos] y después se vuelve a leer, para
  /// que un horario editado por el cuidador no tarde indefinidamente en verse.
  ///
  /// [forzar] ignora tanto el atajo como la caché de tratamientos; se usa al
  /// cargar el paciente y al volver del fondo, que son los momentos en los que
  /// interesa asegurar que el estado real se miró de verdad.
  Future<List<OmitidaNueva>> reconciliar(
    String pacienteId, {
    DateTime? ahora,
    bool forzar = false,
  }) async {
    final momento = ahora ?? DateTime.now();

    final tratamientos = await _tratamientosDe(pacienteId, forzar: forzar);

    // Aprovecha los mismos disparadores de la reconciliación (arranque,
    // `resumed` y tick de 60 s) para retirar alarmas de tratamientos que ya
    // terminaron. Es idempotente: solo cancela una vez por estado.
    await _cancelarNotificacionesDeFinalizados(tratamientos, momento);

    final vencidas = ranurasVencidas(
      tratamientos: tratamientos,
      ahora: momento,
    );
    final firma = firmaDe(vencidas);
    final firmaTratamientos = _firmaDeTratamientos(tratamientos);
    final evaluarAlertas = _debeEvaluarAlertas(
      tratamientos,
      momento,
      firmaTratamientos,
    );

    if (!forzar && _firma == firma && !evaluarAlertas) return const [];

    // Se releen los registros de la ventana para saber qué falta. El rango
    // arranca a medianoche del primer día revisado y termina mañana, así que
    // cubre con holgura las horas de hoy. Si la alerta de 5 días necesita días
    // más antiguos (por ejemplo, un horario semanal), se amplía el inicio.
    final inicioDia = DateTime(
      momento.year,
      momento.month,
      momento.day,
    ).subtract(Duration(days: ventanaDias - 1));
    var inicioLectura = inicioDia;
    for (final t in tratamientos) {
      final inicioAlerta = AlertaSinTomasService.inicioVentanaAlerta(t, momento);
      if (inicioAlerta != null && inicioAlerta.isBefore(inicioLectura)) {
        inicioLectura = inicioAlerta;
      }
    }
    final existentes = await _fs.getRegistrosEnRango(
      pacienteId,
      inicioLectura,
      inicioDia.add(const Duration(days: ventanaDias + 1)),
    );
    final resueltas = clavesResueltas(existentes);

    final nuevas = <OmitidaNueva>[];
    for (final r in vencidas) {
      if (resueltas.contains(r.clave)) continue;
      await _fs.crearRegistroToma(
        idDoc: idDocumento(r.tratamientoId, r.horaProgramada),
        tratamientoId: r.tratamientoId,
        pacienteId: pacienteId,
        horaProgramada: r.horaProgramada,
        estado: EstadoToma.olvidada,
      );
      // El nombre del medicamento ya está en memoria; no hace falta releerlo.
      var nombreMedicamento = 'Medicamento';
      for (final t in tratamientos) {
        if (t.id == r.tratamientoId) {
          nombreMedicamento = t.nombreMedicamento;
          break;
        }
      }
      nuevas.add(
        OmitidaNueva(
          tratamientoId: r.tratamientoId,
          nombreMedicamento: nombreMedicamento,
          horaProgramada: r.horaProgramada,
        ),
      );
    }

    // La firma se fija al final y no antes: si las escrituras fallaran, el
    // siguiente tick debe reintentarlo en vez de darla por buena.
    _firma = firma;

    // Se evalúa después de escribir las olvidadas: una toma olvidada no cuenta
    // como confirmación, así que no rompe la racha. Si algo falla, no se marca
    // la evaluación como hecha para que el siguiente tick lo reintente.
    final alertasOk = await _evaluarAlertasSinTomas(
      pacienteId,
      tratamientos,
      existentes,
      momento,
    );
    if (alertasOk) {
      _ultimaEvaluacionAlertas = momento;
      _firmaTratamientosAlertas = firmaTratamientos;
    }
    return nuevas;
  }

  /// ¿Hay que releer registros aunque las tomas vencidas no hayan cambiado?
  ///
  /// La alerta de 5 días depende de datos que no están en [firmaDe]: una
  /// confirmación puede romper la racha, el cambio de día mueve la ventana y
  /// el campo `ultimoAvisoSinTomas` cambia al enviar o reiniciar el aviso.
  bool _debeEvaluarAlertas(
    List<Tratamiento> tratamientos,
    DateTime ahora,
    String firmaTratamientos,
  ) {
    if (_ultimaEvaluacionAlertas == null) return true;
    if (!_mismoDia(_ultimaEvaluacionAlertas!, ahora)) return true;
    if (_firmaTratamientosAlertas != firmaTratamientos) return true;

    // Mientras haya un aviso marcado se relee en cada tick: así una toma
    // confirmada reinicia la racha y el campo `ultimoAvisoSinTomas` se limpia
    // en cuanto se detecta, sin esperar al día siguiente.
    for (final t in tratamientos) {
      if (t.ultimoAvisoSinTomas != null) return true;
      if (_avisosSinTomasEnviados.containsKey(t.id)) return true;
    }
    return false;
  }

  Future<bool> _evaluarAlertasSinTomas(
    String pacienteId,
    List<Tratamiento> tratamientos,
    List<RegistroToma> registros,
    DateTime ahora,
  ) async {
    var ok = true;

    for (final t in tratamientos) {
      final hayAlerta = AlertaSinTomasService.hayAlerta(
        tratamiento: t,
        registros: registros,
        ahora: ahora,
      );

      if (!hayAlerta) {
        final teniaAviso =
            t.ultimoAvisoSinTomas != null ||
            _avisosSinTomasEnviados.containsKey(t.id);
        if (!teniaAviso) continue;

        try {
          // Una toma confirmada (o cualquier cambio que saque al tratamiento
          // de la alerta) reinicia el estado para una racha futura.
          await _fs.limpiarAvisoSinTomas(t.id);
          _avisosSinTomasEnviados.remove(t.id);
        } catch (e) {
          ok = false;
          if (kDebugMode) {
            debugPrint('No se pudo reiniciar ultimoAvisoSinTomas: $e');
          }
        }
        continue;
      }

      final avisoEnCampo = t.ultimoAvisoSinTomas;
      final avisoEnMemoria = _avisosSinTomasEnviados[t.id];
      final yaAvisadoHoy =
          (avisoEnCampo != null && _mismoDia(avisoEnCampo, ahora)) ||
          (avisoEnMemoria != null && _mismoDia(avisoEnMemoria, ahora));
      if (yaAvisadoHoy) continue;

      if (!_avisosSinTomasEnCurso.add(t.id)) continue;
      try {
        // Se guarda primero la fecha: si dos reconciliaciones se solapan, la
        // segunda no vuelve a enviar el push. Si la escritura falla, no se
        // envía nada para no dejar el aviso sin registrar.
        await _fs.marcarAvisoSinTomas(t.id, ahora);
        _avisosSinTomasEnviados[t.id] = ahora;
        unawaited(
          _push.notificarAlertaSinTomas(
            pacienteId: pacienteId,
            nombreMedicamento: t.nombreMedicamento,
          ),
        );
      } catch (e) {
        ok = false;
        if (kDebugMode) {
          debugPrint('No se pudo marcar/enviar la alerta sin tomas: $e');
        }
      } finally {
        _avisosSinTomasEnCurso.remove(t.id);
      }
    }

    return ok;
  }

  static String _firmaDeTratamientos(List<Tratamiento> tratamientos) {
    return tratamientos.map((t) {
      final horarios = t.horarios
          .map((h) => '${h.hora}[${(h.dias.toList()..sort()).join(',')}]')
          .join(';');
      return '${t.id}|${t.fechaInicio?.toIso8601String()}|'
          '${t.duracionDias}|$horarios|'
          '${t.ultimoAvisoSinTomas?.toIso8601String()}';
    }).join('||');
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<List<Tratamiento>> _tratamientosDe(
    String pacienteId, {
    required bool forzar,
  }) async {
    final ahora = DateTime.now();
    final cache = _tratamientosCache;
    final leida = _cacheLeida;
    final vigente =
        cache != null &&
        leida != null &&
        ahora.difference(leida) < vigenciaCacheTratamientos;
    if (!forzar && vigente) return cache;

    try {
      final tratamientos = await _fs
          .streamTratamientosDePaciente(pacienteId)
          .first;
      _tratamientosCache = tratamientos;
      _cacheLeida = ahora;
      return tratamientos;
    } catch (_) {
      // Sin red no se puede recalcular nada. Se devuelve la caché aunque esté
      // vencida: peor un cálculo con datos viejos que no registrar nada.
      return cache ?? const [];
    }
  }

  Future<void> _cancelarNotificacionesDeFinalizados(
    List<Tratamiento> tratamientos,
    DateTime ahora,
  ) async {
    final claves = <String>{};
    for (final t in tratamientos) {
      if (VigenciaTratamiento.estaVigente(t, ahora)) continue;

      final clave = _claveEstadoFinalizado(t);
      claves.add(clave);
      if (_finalizadosCancelados.contains(clave)) continue;

      try {
        await _notif.cancelarNotificacionesDeTratamiento(
          tratamientoId: t.id,
          horarios: t.horarios,
        );
        _finalizadosCancelados.add(clave);
        if (kDebugMode) {
          debugPrint('Notificaciones canceladas: el tratamiento terminó.');
        }
      } catch (e) {
        // Best-effort: el siguiente tick reintenta.
        if (kDebugMode) {
          debugPrint(
            'No se pudieron cancelar las notificaciones del tratamiento '
            'finalizado: $e',
          );
        }
      }
    }

    // Si un tratamiento vuelve a estar vigente (el cuidador amplió la
    // duración), se olvida su estado para poder cancelarlo si vuelve a
    // terminar.
    _finalizadosCancelados.removeWhere((clave) => !claves.contains(clave));
  }

  static String _claveEstadoFinalizado(Tratamiento t) {
    final horarios = t.horarios
        .map((h) => '${h.hora}[${(h.dias.toList()..sort()).join(',')}]')
        .join(';');
    return '${t.id}|${t.fechaInicio?.toIso8601String()}|'
        '${t.duracionDias}|$horarios';
  }

  /// Olvida la caché y la firma. Se usa al desvincular para que el siguiente
  /// paciente no herede el estado del anterior.
  void invalidar() {
    _tratamientosCache = null;
    _cacheLeida = null;
    _firma = null;
    _finalizadosCancelados.clear();
    _avisosSinTomasEnviados.clear();
    _avisosSinTomasEnCurso.clear();
    _ultimaEvaluacionAlertas = null;
    _firmaTratamientosAlertas = null;
  }
}
