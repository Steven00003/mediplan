import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/paciente.dart';
import '../models/registro_toma.dart';
import '../services/firestore_service.dart';
import '../services/local_store.dart';
import '../services/omitidas_service.dart';
import '../services/notificaciones_service.dart';
import '../services/push_service.dart';
import '../services/vinculacion_service.dart';
import '../utils/reingreso_paciente.dart';

/// Mantiene el estado global de la app según el rol en uso.
///
/// La app soporta dos flujos mutuamente excluyentes:
///  - Rol Doctor (requiere login Firebase).
///  - Rol Paciente (se vincula por código, persiste localmente).
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final FirestoreService _fs = FirestoreService();
  final NotificacionesService _notif = NotificacionesService();
  final OmitidasService _omitidas = OmitidasService();
  final PushService _push = PushService();

  /// Ranuras olvidadas de las que ya se avisó al cuidador en esta sesión.
  ///
  /// `reconciliar()` solo devuelve lo que escribió en esta pasada, pero un tick
  /// de 60s y un `resumed` solapados pueden escribir la misma toma en dos
  /// pasadas: este set evita el push duplicado. Una ranura olvidada nunca se
  /// vuelve "nueva" dentro de una sesión, así que no necesita expirar.
  final Set<String> _olvidadasAvisadas = {};

  /// Revisa las tomas olvidadas mientras el rol paciente está activo.
  ///
  /// Es un tick grueso a propósito: la ruta rápida de `OmitidasService`
  /// calcula el conjunto de tomas vencidas en memoria y sale sin tocar Firestore
  /// si no cambió, así que este intervalo no implica lecturas ni escrituras
  /// mientras no haya nada que reconciliar.
  static const Duration _intervaloOmitidas = Duration(seconds: 60);

  Timer? _timerOmitidas;

  /// `true` mientras haya una pantalla de alarma abierta.
  ///
  /// Bloquea la reconciliación: una toma no se da por olvidada mientras el
  /// paciente está mirando su propia alarma (ver `_abrirAlarma` en
  /// `medicamentos_proximos_screen.dart`).
  bool _alarmaAbierta = false;

  /// Escucha el documento del paciente para detectar desvinculación o borrado.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pacienteSub;

  // Rol paciente
  Paciente? _pacienteVinculado;
  bool _cargandoPaciente = true;

  Paciente? get pacienteVinculado => _pacienteVinculado;
  bool get cargandoPaciente => _cargandoPaciente;
  bool get esPaciente => _pacienteVinculado != null;

  /// Verifica al iniciar si este dispositivo ya está vinculado como paciente.
  ///
  /// Solo se desvincula ante señales DEFINITIVAS del servidor: el doc ya no
  /// existe, `dispositivoVinculadoId` ya no coincide con el UID de la sesión
  /// anónima, o la lectura fue rechazada por permisos. Ante errores de red
  /// (unavailable) el paciente sigue siendo paciente con sus datos locales.
  Future<void> cargarEstadoInicial() async {
    _cargandoPaciente = true;
    notifyListeners();
    WidgetsBinding.instance.addObserver(this);

    try {
      // El paciente usa sesión anónima; la aseguramos antes de leer Firestore.
      await VinculacionService().asegurarSesionAnonima();

      final pacienteId = await LocalStore.getPacienteVinculadoId();
      if (pacienteId != null && pacienteId.isNotEmpty) {
        final leido = await _cargarPacienteLeido(pacienteId);
        if (leido) {
          _escucharPacienteDoc(pacienteId);
        }
      }
    } finally {
      _cargandoPaciente = false;
      notifyListeners();
    }
  }

  /// Volver del fondo es el momento clave: los timers de Dart se suspenden en
  /// background, así que es el disparador fiable para reconciliar tras una
  /// ausencia larga (y para el caso de una alarma del sistema que abrió la app).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconciliarOmitidas(forzar: true));
    }
  }

  /// `true` mientras una alarma está en pantalla. Lo consulta también el
  /// arranque para no abrir una segunda alarma desde una notificación.
  bool get alarmaAbierta => _alarmaAbierta;

  /// Marca (desde la pantalla del paciente) que hay una alarma abierta, para que
  /// la reconciliación no declare olvidada la toma que el paciente está viendo.
  void setAlarmaAbierta(bool abierta) {
    _alarmaAbierta = abierta;
  }

  /// Reconcilia las tomas olvidadas del paciente vinculado.
  ///
  /// Es idempotente y sin efectos observables en la UI, así que no dispara
  /// `notifyListeners()`: evitamos un `build` inútil por cada tick.
  Future<void> _reconciliarOmitidas({bool forzar = false}) async {
    final pacienteId = _pacienteVinculado?.id;
    if (pacienteId == null || _alarmaAbierta) return;
    try {
      final nuevas = await _omitidas.reconciliar(pacienteId, forzar: forzar);
      // El aviso de una toma olvidada es best-effort, igual que el de las
      // confirmaciones: la toma ya quedó registrada en Firestore, que es la
      // fuente de verdad, y el push no puede (ni debe) hacer fallar nada.
      for (final omitida in nuevas) {
        final clave =
            '${omitida.tratamientoId}|${omitida.horaProgramada.millisecondsSinceEpoch}';
        if (!_olvidadasAvisadas.add(clave)) continue;
        unawaited(_push.notificarConfirmacion(
          pacienteId: pacienteId,
          nombreMedicamento: omitida.nombreMedicamento,
          hora: omitida.horaTxt,
          estado: EstadoToma.olvidada,
        ));
      }
    } catch (_) {
      // Reconciliar es una mejora best-effort: un fallo puntual (sin red, sin
      // índice compuesto aún) no debe sacar al paciente de la app. El siguiente
      // tick reintenta.
    }
  }

  void _arrancarTimerOmitidas() {
    _timerOmitidas?.cancel();
    _timerOmitidas = Timer.periodic(_intervaloOmitidas, (_) {
      unawaited(_reconciliarOmitidas());
    });
  }

  void _pararTimerOmitidas() {
    _timerOmitidas?.cancel();
    _timerOmitidas = null;
  }

  @override
  void dispose() {
    _pararTimerOmitidas();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Devuelve true si se leyó (o reconstruyó localmente) un paciente y se
  /// dejó en [_pacienteVinculado]; false si se desvinculó.
  Future<bool> _cargarPacienteLeido(String pacienteId) async {
    Paciente? paciente;
    var leidoDelServidor = true;
    try {
      // Fuerza lectura desde el servidor tras vinculación/arranque para evitar
      // leer un documento obsoleto desde la caché local de Firestore.
      paciente = await _fs.getPaciente(
        pacienteId,
        options: const GetOptions(source: Source.server),
      );
    } catch (e) {
      // Una señal definitiva (permisos) manda aunque haya caché: el cuidador
      // pudo desvincular el dispositivo y no queremos seguir mostrando datos
      // viejos. Solo los errores de red caen al fallback de caché.
      if (_esErrorDefinitivo(e)) {
        await desvincularPaciente();
        return false;
      }
      try {
        paciente = await _fs.getPaciente(
          pacienteId,
          options: const GetOptions(source: Source.cache),
        );
        leidoDelServidor = false;
      } catch (_) {
        // Error de red/unavailable y sin caché usable: no desvinculamos.
        // El paciente sigue con sus medicamentos y alarmas usando datos locales.
        leidoDelServidor = false;
        paciente = Paciente(
          id: pacienteId,
          nombre: await LocalStore.getPacienteVinculadoNombre() ?? 'Paciente',
          cuidadorId: '',
          codigoVinculacion: '',
        );
      }
    }

    if (paciente == null) {
      // El perfil ya no existe en el servidor: desvinculamos.
      await desvincularPaciente();
      return false;
    }

    if (leidoDelServidor) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || paciente.dispositivoVinculadoId != uid) {
        // El dispositivo ya no corresponde a este perfil (desvinculado o
        // re-vinculado a otro dispositivo).
        await desvincularPaciente();
        return false;
      }
      // Mantener fresca la vinculación recordada con los datos del servidor.
      final recordada = await LocalStore.getUltimaVinculacion();
      await LocalStore.guardarUltimaVinculacion(
        pacienteId: paciente.id,
        codigo: paciente.codigoVinculacion.trim().isNotEmpty
            ? paciente.codigoVinculacion
            : (recordada?.codigo ?? ''),
        nombre: paciente.nombre,
      );
    }

    _pacienteVinculado = paciente;
    _arrancarTimerOmitidas();
    // Arranque en frío: es el único punto que cubre de forma fiable el caso de
    // un paciente que estuvo días sin abrir la app (no hay ningún listener de
    // notificaciones: tocar la alarma del sistema solo lanza la app).
    unawaited(_reconciliarOmitidas(forzar: true));
    return true;
  }

  /// Escucha el doc del paciente: ante una señal definitiva del servidor
  /// (doc borrado, dispositivoVinculadoId distinto del UID, error de permisos)
  /// se desvincula. Los snapshots en caché y los errores de red se ignoran para
  /// no cortar al paciente que está offline.
  void _escucharPacienteDoc(String pacienteId) {
    _pacienteSub?.cancel();
    _pacienteSub = _fs.streamPacienteDoc(pacienteId).listen(
      (snap) {
        if (snap.metadata.isFromCache) return; // solo dato del servidor
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final desvinculado = !snap.exists ||
            uid == null ||
            (snap.data()?['dispositivoVinculadoId'] as String?) != uid;
        if (desvinculado) {
          unawaited(desvincularPaciente());
        }
      },
      onError: (Object e) {
        if (_esErrorDefinitivo(e)) {
          unawaited(desvincularPaciente());
        }
        // Errores de red/unavailable: se ignoran, el paciente sigue.
      },
    );
  }

  /// Solo los errores de permiso del servidor cuentan como señal definitiva.
  bool _esErrorDefinitivo(Object e) {
    return e is FirebaseException && e.code == 'permission-denied';
  }

  /// Establece el paciente vinculado tras un código válido.
  Future<void> establecerPaciente(Paciente paciente) async {
    await LocalStore.guardarPacienteVinculado(paciente.id, paciente.nombre);
    if (paciente.codigoVinculacion.trim().isNotEmpty) {
      await LocalStore.guardarUltimaVinculacion(
        pacienteId: paciente.id,
        codigo: paciente.codigoVinculacion,
        nombre: paciente.nombre,
      );
    }
    _pacienteVinculado = paciente;
    _omitidas.invalidar();
    _arrancarTimerOmitidas();
    unawaited(_reconciliarOmitidas(forzar: true));
    _escucharPacienteDoc(paciente.id);
    notifyListeners();
  }

  /// Limpia el flag/LocalStore de paciente tras un login de cuidador exitoso
  /// en el mismo dispositivo. No cancela las alarmas ni cierra la sesión.
  Future<void> limpiarFlagDePaciente() async {
    await _pacienteSub?.cancel();
    _pacienteSub = null;
    await LocalStore.limpiarPacienteVinculado();
    _pacienteVinculado = null;
    _pararTimerOmitidas();
    _omitidas.invalidar();
    notifyListeners();
  }

  /// Salida del modo paciente **sin cerrar la sesión anónima**.
  ///
  /// Conservar el UID es lo que permite que "Continuar como paciente" valide
  /// contra el servidor y vuelva a entrar sin pedir el código. Guarda la última
  /// vinculación en una clave separada del flag de paciente activo y cancela
  /// las alarmas/notificaciones locales de este dispositivo.
  Future<void> salirDelModoPaciente() async {
    final paciente = _pacienteVinculado;
    if (paciente != null) {
      final recordada = await LocalStore.getUltimaVinculacion();
      await LocalStore.guardarUltimaVinculacion(
        pacienteId: paciente.id,
        codigo: paciente.codigoVinculacion.trim().isNotEmpty
            ? paciente.codigoVinculacion
            : (recordada?.codigo ?? ''),
        nombre: paciente.nombre.trim().isNotEmpty
            ? paciente.nombre
            : (recordada?.nombre ?? ''),
      );
    }
    await _limpiarPacienteLocal(
      borrarRecordada: false,
      cerrarSesionAnonima: false,
    );
  }

  /// Reingresa con la vinculación recordada, validando contra el servidor que
  /// `pacientes/{id}.dispositivoVinculadoId` sigue siendo el UID actual.
  ///
  /// No hace un `get()` directo a un documento que las reglas podrían rechazar:
  /// usa una query filtrada por `dispositivoVinculadoId == uid`, condición que
  /// la regla de lectura puede comprobar. Si el servidor ya no lo reconoce,
  /// borra la vinculación recordada y vuelve a la selección de rol sin lanzar
  /// errores técnicos a la UI.
  Future<ResultadoReingresoPaciente> reingresarPaciente() async {
    final recordada = await LocalStore.getUltimaVinculacion();
    if (recordada == null || !recordada.esValida) {
      return ResultadoReingresoPaciente.sinVinculacionRecordada;
    }

    try {
      await VinculacionService().asegurarSesionAnonima();
    } catch (_) {
      return ResultadoReingresoPaciente.errorRed;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return ResultadoReingresoPaciente.errorRed;

    try {
      final paciente = await _fs.getPacienteVinculadoParaReingreso(
        recordada.pacienteId,
        uid,
        source: Source.server,
      );
      if (paciente == null || paciente.dispositivoVinculadoId != uid) {
        await _limpiarPacienteLocal(
          borrarRecordada: true,
          cerrarSesionAnonima: false,
        );
        return ResultadoReingresoPaciente.noCoincide;
      }

      await _activarPaciente(paciente, codigoRecordado: recordada.codigo);
      // Se reprograman todas las alarmas después de validar; si falla la
      // consulta de tratamientos, el reingreso no se pierde.
      await _programarAlarmasDePaciente(paciente.id);
      return ResultadoReingresoPaciente.exito;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _limpiarPacienteLocal(
          borrarRecordada: true,
          cerrarSesionAnonima: false,
        );
        return ResultadoReingresoPaciente.noCoincide;
      }
      // Red/timeout: se conserva la vinculación recordada para reintentar.
      return ResultadoReingresoPaciente.errorRed;
    } catch (_) {
      return ResultadoReingresoPaciente.errorRed;
    }
  }

  /// Deja al paciente activo y persiste la vinculación recordada.
  Future<void> _activarPaciente(
    Paciente paciente, {
    required String codigoRecordado,
  }) async {
    await LocalStore.guardarPacienteVinculado(paciente.id, paciente.nombre);
    await LocalStore.guardarUltimaVinculacion(
      pacienteId: paciente.id,
      codigo: paciente.codigoVinculacion.trim().isNotEmpty
          ? paciente.codigoVinculacion
          : codigoRecordado,
      nombre: paciente.nombre,
    );

    _pacienteVinculado = paciente;
    _omitidas.invalidar();
    _arrancarTimerOmitidas();
    unawaited(_reconciliarOmitidas(forzar: true));
    _escucharPacienteDoc(paciente.id);
    notifyListeners();
  }

  /// Cancela las alarmas locales y vuelve a programar todas las del paciente.
  ///
  /// Es best-effort: si la lectura de tratamientos falla, no se cancelan las
  /// alarmas existentes y el reingreso sigue siendo válido.
  Future<void> _programarAlarmasDePaciente(String pacienteId) async {
    try {
      final tratamientos = await _fs.getTratamientosDePaciente(
        pacienteId,
        options: const GetOptions(source: Source.server),
      );
      await _notif.cancelarTodas();
      for (final tratamiento in tratamientos) {
        for (final horario in tratamiento.horarios) {
          try {
            await _notif.programarAlarmasDeHorario(
              tratamientoId: tratamiento.id,
              horario: horario,
              nombreMedicamento: tratamiento.nombreMedicamento,
            );
          } catch (e) {
            debugPrint(
              'No se pudo programar una alarma de ${tratamiento.id}: $e',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('No se pudieron reprogramar las alarmas: $e');
    }
  }

  /// Limpia el paciente de la memoria y del almacenamiento local.
  ///
  /// [borrarRecordada] distingue la salida normal (se conserva) de la
  /// desvinculación definitiva o de una vinculación que ya no coincide.
  /// [cerrarSesionAnonima] solo se usa en la desvinculación definitiva: la
  /// salida normal conserva el UID para poder reingresar.
  Future<void> _limpiarPacienteLocal({
    required bool borrarRecordada,
    required bool cerrarSesionAnonima,
  }) async {
    await _pacienteSub?.cancel();
    _pacienteSub = null;
    await LocalStore.limpiarPacienteVinculado();
    if (borrarRecordada) {
      await LocalStore.limpiarUltimaVinculacion();
    }
    await _notif.cancelarTodas();
    if (cerrarSesionAnonima) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }
    }
    _pacienteVinculado = null;
    _alarmaAbierta = false;
    _pararTimerOmitidas();
    _omitidas.invalidar();
    _olvidadasAvisadas.clear();
    notifyListeners();
  }

  /// Desvinculación definitiva (doc borrado, UID distinto o permiso denegado):
  /// borra también la vinculación recordada, como antes, para que no se ofrezca
  /// un reingreso que el servidor ya no reconoce.
  Future<void> desvincularPaciente() async {
    await _limpiarPacienteLocal(
      borrarRecordada: true,
      cerrarSesionAnonima: true,
    );
  }
}