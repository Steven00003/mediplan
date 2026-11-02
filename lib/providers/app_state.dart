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
      // Fallback explícito a caché local si no hay conexión o el servidor no responde.
      // Este es un camino de borde, no el camino normal.
      try {
        paciente = await _fs.getPaciente(
          pacienteId,
          options: const GetOptions(source: Source.cache),
        );
        leidoDelServidor = false;
      } catch (_) {
        if (_esErrorDefinitivo(e)) {
          await desvincularPaciente();
          return false;
        }
        // Error definitivo detectado en el primer intento o sin datos en caché.
        if (_esErrorDefinitivo(e)) {
          await desvincularPaciente();
          return false;
        }
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

  /// Desvincula el dispositivo: limpia el estado local, cancela las alarmas y
  /// cierra la sesión anónima (solo si es la sesión activa). El documento en
  /// Firestore NO se toca: el paciente no puede desvincularse solo (reglas),
  /// solo el cuidador dueño puede liberarlo desde el dashboard.
  Future<void> desvincularPaciente() async {
    await _pacienteSub?.cancel();
    _pacienteSub = null;
    await LocalStore.limpiarPacienteVinculado();
    await _notif.cancelarTodas();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      await FirebaseAuth.instance.signOut();
    }
    _pacienteVinculado = null;
    _alarmaAbierta = false;
    _pararTimerOmitidas();
    _omitidas.invalidar();
    notifyListeners();
  }
}