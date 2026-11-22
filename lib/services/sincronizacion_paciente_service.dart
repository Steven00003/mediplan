import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../constants.dart';
import '../models/paciente.dart';
import '../models/tratamiento.dart';
import '../utils/errores_amigables.dart';
import '../utils/sincronizacion_paciente.dart';
import 'estado_dispositivo_service.dart';
import 'firestore_service.dart';
import 'limpieza_paciente_service.dart';
import 'local_store.dart';
import 'notificaciones_service.dart';
import 'push_service.dart';

/// Coordina el aviso FCM cuidador → paciente y el rearme en segundo plano.
///
/// El mensaje solo aporta `tipo=sync` y `pacienteId`; todo lo demás se vuelve a
/// leer de Firestore y se valida contra la vinculación local.
class SincronizacionPacienteService {
  static final SincronizacionPacienteService _instancia =
      SincronizacionPacienteService._interno();

  factory SincronizacionPacienteService() => _instancia;

  SincronizacionPacienteService._interno()
    : _fs = FirestoreService(),
      _notif = NotificacionesService(),
      _estado = EstadoDispositivoService(),
      _push = PushService(),
      _timeoutLectura = const Duration(seconds: 8),
      _debounce = DebounceSincronizacion();

  /// Constructor con dependencias sustituibles para pruebas futuras.
  @visibleForTesting
  SincronizacionPacienteService.conDependencias({
    FirestoreService? firestore,
    NotificacionesService? notificaciones,
    EstadoDispositivoService? estado,
    PushService? push,
    this._timeoutLectura = const Duration(seconds: 8),
    Duration esperaDebounce = debounceSincronizacionPaciente,
  }) : _fs = firestore ?? FirestoreService(),
       _notif = notificaciones ?? NotificacionesService(),
       _estado = estado ?? EstadoDispositivoService(),
       _push = push ?? PushService(),
       _debounce = DebounceSincronizacion(espera: esperaDebounce);

  final FirestoreService _fs;
  final NotificacionesService _notif;
  final EstadoDispositivoService _estado;
  final PushService _push;
  final Duration _timeoutLectura;
  final DebounceSincronizacion _debounce;

  final Map<String, Timer> _temporizadores = {};
  StreamSubscription<RemoteMessage>? _suscripcionMensajes;

  /// Se llama una vez al inicializar la app, con Firebase ya listo.
  void iniciarEscuchaAppAbierta() {
    _suscripcionMensajes ??= FirebaseMessaging.onMessage.listen((mensaje) {
      final datos = mensaje.data;
      if (datos.isEmpty) return;
      unawaited(procesarMensaje(datos));
    });
  }

  /// Agrupa los cambios de tratamiento durante [debounceSincronizacionPaciente]
  /// y después envía un único push al paciente.
  ///
  /// No lanza hacia afuera: un fallo del push nunca debe romper el guardado del
  /// cuidador ni mostrarle un error.
  void programarEnvio(String pacienteId) {
    final id = pacienteId.trim();
    if (id.isEmpty) return;

    final ahora = DateTime.now();
    final generacion = _debounce.registrar(id, ahora);
    _temporizadores.remove(id)?.cancel();

    final retraso =
        _debounce.retrasoPendiente(id, generacion, ahora) ??
        debounceSincronizacionPaciente;
    _temporizadores[id] = Timer(
      retraso,
      () => unawaited(_enviarCuandoVenza(id, generacion)),
    );
  }

  /// Cancela un envío pendiente (por ejemplo, si se cierra la sesión).
  void cancelarEnvio(String pacienteId) {
    _temporizadores.remove(pacienteId)?.cancel();
  }

  Future<void> _enviarCuandoVenza(String pacienteId, int generacion) async {
    _temporizadores.remove(pacienteId);
    if (!_debounce.debeEnviar(pacienteId, generacion, DateTime.now())) return;
    _debounce.limpiar(pacienteId, generacion);
    await _push.notificarSincronizacionAlPaciente(pacienteId);
  }

  /// Procesa un mensaje `sync` recibido con la app abierta o cerrada.
  ///
  /// Devuelve `true` solo si este teléfono validó la vinculación y rearmó. Los
  /// mensajes de otro paciente o de un dispositivo no vinculado se ignoran sin
  /// escribir nada ni revelar información.
  Future<bool> procesarMensaje(
    Map<String, dynamic> datos, {
    bool prepararNotificaciones = false,
  }) async {
    final pacienteIdMensaje = pacienteIdDesdeMensajeSincronizacion(datos);
    if (pacienteIdMensaje == null) return false;

    final pacienteIdLocal = await LocalStore.getPacienteVinculadoId();
    if (pacienteIdLocal == null || pacienteIdLocal.trim().isEmpty) {
      return false;
    }

    final usuario = await _usuarioActual();
    if (usuario == null ||
        !usuario.isAnonymous ||
        pacienteIdMensaje != pacienteIdLocal.trim()) {
      return false;
    }

    try {
      final paciente = await _leerPaciente(pacienteIdLocal);
      if (paciente == null) {
        await _olvidarPaciente(
          pacienteIdLocal,
          prepararNotificaciones: prepararNotificaciones,
        );
        return false;
      }

      // La comprobación definitiva: el documento del servidor debe seguir
      // apuntando al mismo UID anónimo. El id del mensaje solo sirve para
      // localizar el documento; no autoriza nada por sí mismo.
      if (!debeProcesarSincronizacion(
        pacienteIdMensaje: pacienteIdMensaje,
        pacienteIdLocal: pacienteIdLocal,
        uidActual: usuario.uid,
        dispositivoVinculadoId: paciente.dispositivoVinculadoId,
        sesionAnonima: usuario.isAnonymous,
      )) {
        return false;
      }

      final tratamientos = await _leerTratamientos(pacienteIdLocal);
      if (prepararNotificaciones) {
        await _notif.prepararParaSegundoPlano();
      }
      await _notif.rearmarAlarmasDeTratamientos(
        tratamientos: tratamientos,
        ahora: DateTime.now(),
      );

      // Respeta el throttle de 30 minutos de EstadoDispositivoService.
      await _estado.reportar(pacienteIdLocal);
      await LocalStore.limpiarUltimoErrorSincronizacion();
      return true;
    } catch (e) {
      // El documento existe pero este teléfono ya no puede leerlo: es una señal
      // definitiva de que el médico eliminó el perfil (o lo desvinculó).
      if (_esPermisoDenegado(e)) {
        await _olvidarPaciente(
          pacienteIdLocal,
          prepararNotificaciones: prepararNotificaciones,
        );
        return false;
      }
      await _registrarError(e);
      return false;
    }
  }

  Future<void> _olvidarPaciente(
    String pacienteId, {
    required bool prepararNotificaciones,
  }) async {
    try {
      if (prepararNotificaciones) {
        await _notif.prepararParaSegundoPlano();
      }
      await LimpiezaPacienteService().olvidarPaciente(
        pacienteId: pacienteId,
        mensajeSeleccionRol: mensajePerfilPacienteEliminado,
      );
    } catch (e) {
      await _registrarError(e);
    }
  }

  Future<User?> _usuarioActual() async {
    final actual = FirebaseAuth.instance.currentUser;
    if (actual != null) return actual;
    try {
      return await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((usuario) => usuario != null)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return FirebaseAuth.instance.currentUser;
    }
  }

  Future<Paciente?> _leerPaciente(String pacienteId) async {
    try {
      return await _fs
          .getPaciente(
            pacienteId,
            options: const GetOptions(source: Source.server),
          )
          .timeout(_timeoutLectura);
    } catch (e) {
      // Un `permission-denied` significa que este teléfono ya no puede leer el
      // documento (desvinculado o borrado): no se usa caché vieja.
      if (_esPermisoDenegado(e)) rethrow;
    }
    return await _fs.getPaciente(
      pacienteId,
      options: const GetOptions(source: Source.cache),
    );
  }

  Future<List<Tratamiento>> _leerTratamientos(String pacienteId) async {
    try {
      return await _fs
          .getTratamientosDePaciente(
            pacienteId,
            options: const GetOptions(source: Source.server),
          )
          .timeout(_timeoutLectura);
    } catch (e) {
      if (_esPermisoDenegado(e)) rethrow;
    }
    return await _fs.getTratamientosDePaciente(
      pacienteId,
      options: const GetOptions(source: Source.cache),
    );
  }

  bool _esPermisoDenegado(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  Future<void> _registrarError(Object error) async {
    if (kDebugMode) {
      debugPrint('No se pudo procesar la sincronización del paciente: $error');
    }
    try {
      await LocalStore.guardarUltimoErrorSincronizacion(
        mensajeErrorAmigable(
          error,
          contexto: 'No se pudo sincronizar el cambio de tratamiento',
        ),
      );
    } catch (_) {
      // El último error es informativo; nunca debe tumbar el aislamiento de FCM.
    }
  }
}

/// Fija la zona IANA real del dispositivo en el isolate de FCM.
///
/// Usa `flutter_timezone` porque el canal nativo de la app (`timeZoneId`) no
/// está registrado en el isolate de fondo. Lanza si no puede determinarse.
Future<void> configurarZonaHorariaSegundoPlano() async {
  tz_data.initializeTimeZones();
  final info = await FlutterTimezone.getLocalTimezone();
  final id = info.identifier.trim();
  if (id.isEmpty) {
    throw StateError('No se pudo determinar la zona horaria del dispositivo.');
  }
  tz.setLocalLocation(tz.getLocation(id));
}
