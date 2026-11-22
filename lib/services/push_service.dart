import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'firestore_service.dart';
import 'notificaciones_service.dart';

/// Push real del paciente al cuidador con la API HTTP v1 de FCM, sin Cloud
/// Functions ni servidor: el dispositivo del paciente firma un JWT con la
/// cuenta de servicio y llama directo a `messages:send`.
///
/// ⚠️ SEGURIDAD: la credencial viaja DENTRO del APK
/// (`assets/secrets/fcm_service_account.json`) y es extraíble por cualquiera.
/// El rol de la cuenta debe limitarse a `cloudmessaging.messages.create`. Ver
/// `assets/secrets/README.md` para el detalle y las mitigaciones.
///
/// Todo lo de aquí es **best effort**: ningún método lanza hacia afuera, ninguno
/// bloquea la confirmación de la toma y, si falta la credencial o la red, la app
/// sigue funcionando sin push.
class PushService {
  static final PushService _instancia = PushService._interno();
  factory PushService() => _instancia;
  PushService._interno();

  /// Credencial de la cuenta de servicio. Si no existe, el push queda apagado.
  static const String rutaCredencial =
      'assets/secrets/fcm_service_account.json';

  static const String _scope =
      'https://www.googleapis.com/auth/firebase.messaging';

  /// Proyecto de Firebase de MediPlan (ver `firebase_options.dart`).
  static const String _proyecto = 'mediplan-35953';

  static const Duration _timeout = Duration(seconds: 10);

  final FirestoreService _fs = FirestoreService();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  ServiceAccountCredentials? _credenciales;
  http.Client? _cliente;
  String? _tokenActual;
  StreamSubscription<String>? _suscripcionToken;
  bool _pushHabilitado = false;

  /// Rol que está usando este teléfono ahora mismo. El token FCM es el mismo
  /// para ambos roles, pero se publica en un campo distinto de Firestore.
  _RolPush _rol = _RolPush.ninguno;
  String? _pacienteIdActual;

  /// ¿Se pudo leer la credencial? Si es false no hay push y el cuidador debe
  /// seguir apoyándose en las notificaciones locales del dashboard.
  bool get pushHabilitado => _pushHabilitado;

  /// Lado app: lee la credencial (sin red, solo parsea el JSON). Se llama una
  /// vez desde `BootstrapScreen`.
  Future<void> inicializar() async {
    try {
      final texto = await rootBundle.loadString(rutaCredencial);
      _credenciales = ServiceAccountCredentials.fromJson(
        jsonDecode(texto) as Map<String, dynamic>,
      );
      _pushHabilitado = true;
    } catch (e) {
      _pushHabilitado = false;
      if (kDebugMode) {
        debugPrint('Push deshabilitado: no se pudo leer la credencial.');
      }
    }
  }

  /// Lado cuidador: pide permiso, obtiene el token, lo publica en sus pacientes
  /// y escucha las rotaciones que hace FCM. Se llama al abrir el dashboard.
  ///
  /// Best-effort: nunca lanza ni interrumpe al usuario; si algo falla, solo se
  /// registra en el log.
  Future<void> registrarCuidador() async {
    if (_auth.currentUser == null) return;
    _rol = _RolPush.cuidador;
    _pacienteIdActual = null;
    try {
      _suscripcionToken ??= _messaging.onTokenRefresh.listen(
        (token) => unawaited(_actualizarToken(token)),
      );

      // Permiso de notificaciones (Android 13+). No bloquea el registro: el
      // token se obtiene y publica aunque esté denegado, y así el paciente ya
      // podrá avisar en cuanto el usuario conceda el permiso.
      try {
        final ajustes = await _messaging.requestPermission();
        if (ajustes.authorizationStatus == AuthorizationStatus.denied) {
          if (kDebugMode) {
            debugPrint('FCM: permiso de notificaciones denegado');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FCM: no se pudo pedir el permiso de notificaciones: $e');
        }
      }

      _tokenActual = await _obtenerToken();
      await _publicarToken(_tokenActual);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo registrar el dispositivo: $e');
      }
    }
  }

  /// Reintenta `getToken()` (hasta 3 veces) porque en Android puede devolver
  /// null de forma transitoria.
  Future<String?> _obtenerToken() async {
    for (var intento = 1; intento <= 3; intento++) {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) return token;
      if (intento < 3) await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  /// Lado cuidador: reintenta publicar el token actual. El dashboard lo llama
  /// cuando cambia su lista de pacientes, para cubrir a los recién creados (que
  /// nacen sin token hasta que este método los alcanza). No depende de la
  /// credencial: publicar el token del cuidador es útil aunque el push aún no
  /// pueda enviarse.
  Future<void> sincronizarTokenConPacientes() async {
    if (_auth.currentUser == null) return;
    try {
      _tokenActual ??= await _messaging.getToken();
      await _publicarToken(_tokenActual);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo sincronizar el token: $e');
      }
    }
  }

  Future<void> _actualizarToken(String token) async {
    _tokenActual = token;
    switch (_rol) {
      case _RolPush.cuidador:
        await _publicarToken(token);
        break;
      case _RolPush.paciente:
        final pacienteId = _pacienteIdActual;
        if (pacienteId != null && pacienteId.isNotEmpty) {
          await _publicarTokenPaciente(pacienteId, token);
        }
        break;
      case _RolPush.ninguno:
        break;
    }
  }

  Future<void> _publicarToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _fs.guardarTokenCuidador(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo guardar el token en Firestore: $e');
      }
    }
  }

  /// Lado paciente: publica el token FCM en `pacientes/{id}.dispositivoFcmToken`.
  ///
  /// Es best-effort: si Firestore falla, las alarmas locales siguen
  /// funcionando y el próximo arranque / refresco de token lo reintenta.
  Future<void> registrarPaciente(String pacienteId) async {
    final id = pacienteId.trim();
    if (id.isEmpty) return;
    _rol = _RolPush.paciente;
    _pacienteIdActual = id;
    try {
      _suscripcionToken ??= _messaging.onTokenRefresh.listen(
        (token) => unawaited(_actualizarToken(token)),
      );
      _tokenActual = await _obtenerToken();
      await _publicarTokenPaciente(id, _tokenActual);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo registrar el teléfono del paciente: $e');
      }
    }
  }

  /// Reintenta publicar el token del paciente al volver del fondo o reingresar.
  Future<void> sincronizarTokenPaciente() async {
    final pacienteId = _pacienteIdActual;
    if (_rol != _RolPush.paciente || pacienteId == null || pacienteId.isEmpty) {
      return;
    }
    try {
      _tokenActual ??= await _obtenerToken();
      await _publicarTokenPaciente(pacienteId, _tokenActual);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo reintentar el token del paciente: $e');
      }
    }
  }

  Future<void> _publicarTokenPaciente(String pacienteId, String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _fs.guardarTokenDispositivo(pacienteId, token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo guardar el token del paciente: $e');
      }
    }
  }

  /// Salida del modo paciente: borra el token de su documento para que el
  /// cuidador no siga enviando avisos a un teléfono que ya no lo usa.
  ///
  /// No llama a `deleteToken()`: el mismo token FCM puede reutilizarse si este
  /// teléfono entra después como cuidador. Solo se elimina el campo de
  /// `pacientes/{id}`. Si el cuidador ya desvinculó el teléfono, la regla puede
  /// rechazar el borrado; se ignora porque el token ya no sirve para ese doc.
  Future<void> cerrarSesionPaciente({String? pacienteId}) async {
    final id = (pacienteId ?? _pacienteIdActual)?.trim() ?? '';
    _rol = _RolPush.ninguno;
    _pacienteIdActual = null;
    if (id.isEmpty) return;
    try {
      await _fs.limpiarTokenDispositivo(id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo borrar el token del paciente: $e');
      }
    }
  }

  /// Cierre de sesión del cuidador: borra el token de Firestore y del dispositivo
  /// para que este teléfono deje de recibir avisos de la cuenta que se va.
  Future<void> cerrarSesionCuidador() async {
    _rol = _RolPush.ninguno;
    _pacienteIdActual = null;
    await _suscripcionToken?.cancel();
    _suscripcionToken = null;
    _tokenActual = null;
    try {
      await _fs.limpiarTokenCuidador();
      await _messaging.deleteToken();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo limpiar el token: $e');
      }
    }
  }

  /// Lado cuidador: avisa al teléfono del paciente de que cambiaron sus
  /// tratamientos para que rearme sus alarmas sin abrir la app.
  ///
  /// Es un mensaje **solo de datos** (sin `notification`) con prioridad alta y
  /// TTL de una hora. No lleva nombre del paciente, medicamento, dosis ni
  /// horarios: únicamente `tipo=sync` y el id que el propio teléfono valida.
  ///
  /// Best-effort: nunca lanza. Un fallo de red no afecta al guardado que ya
  /// hizo el cuidador.
  Future<void> notificarSincronizacionAlPaciente(String pacienteId) async {
    if (!_pushHabilitado) return;
    final id = pacienteId.trim();
    if (id.isEmpty) return;
    try {
      final paciente = await _fs.getPaciente(id);
      final token = paciente?.dispositivoFcmToken?.trim() ?? '';
      if (token.isEmpty) return;
      await notificarSincronizacionConToken(pacienteId: id, token: token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo enviar la sincronización: $e');
      }
    }
  }

  /// Variante que envía el mensaje de sincronización usando un token ya leído.
  ///
  /// Se usa tras borrar un paciente, cuando Firestore ya no es legible. No vuelve
  /// a leer el documento y nunca lanza: un fallo de red no debe afectar el
  /// borrado que ya terminó con éxito.
  Future<void> notificarSincronizacionConToken({
    required String pacienteId,
    required String token,
  }) async {
    if (!_pushHabilitado) return;
    final id = pacienteId.trim();
    final tokenLimpio = token.trim();
    if (id.isEmpty || tokenLimpio.isEmpty) return;
    try {
      final cliente = await _clienteAutenticado();
      if (cliente == null) return;

      final respuesta = await cliente
          .post(
            Uri.parse(
              'https://fcm.googleapis.com/v1/projects/$_proyecto/messages:send',
            ),
            headers: const {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({
              'message': {
                'token': tokenLimpio,
                'android': {'priority': 'high', 'ttl': '3600s'},
                'data': {'tipo': 'sync', 'pacienteId': id},
              },
            }),
          )
          .timeout(_timeout);

      if (respuesta.statusCode != 200 && kDebugMode) {
        debugPrint('FCM: sincronización rechazada (${respuesta.statusCode}).');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo enviar la sincronización: $e');
      }
    }
  }

  /// Lado paciente: avisa al cuidador de que un tratamiento lleva 5 días
  /// programados sin ninguna toma confirmada.
  ///
  /// Es el **único** envío FCM al cuidador. Se llama con `unawaited(...)` y
  /// nunca lanza: el aviso ya quedó marcado en Firestore, que es la fuente de
  /// verdad; el push es solo el extra.
  Future<void> notificarAlertaSinTomas({
    required String pacienteId,
    required String nombreMedicamento,
  }) async {
    if (!_pushHabilitado) return;
    try {
      final paciente = await _fs.getPaciente(pacienteId);
      final token = paciente?.cuidadorFcmToken;
      if (paciente == null || token == null || token.isEmpty) return;

      final cliente = await _clienteAutenticado();
      if (cliente == null) return;

      final respuesta = await cliente
          .post(
            Uri.parse(
              'https://fcm.googleapis.com/v1/projects/$_proyecto/messages:send',
            ),
            headers: const {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({
              'message': {
                'token': token,
                'notification': {
                  'title': '5 días sin tomas',
                  'body':
                      '${paciente.nombre} no ha confirmado ninguna toma de '
                      '$nombreMedicamento en sus últimos 5 días con toma '
                      'programada.',
                },
                'android': {
                  'priority': 'high',
                  'notification': {
                    'channel_id': NotificacionesService.canalCuidadorId,
                  },
                },
                'data': {'tipo': 'alerta_sin_tomas', 'pacienteId': pacienteId},
              },
            }),
          )
          .timeout(_timeout);

      if (respuesta.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('FCM: envío rechazado (${respuesta.statusCode}).');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM: no se pudo enviar el push: $e');
      }
    }
  }

  /// Cliente autenticado con refresco automático del token OAuth2. Se construye
  /// la primera vez que hace falta (una llamada de red) y se reutiliza.
  Future<http.Client?> _clienteAutenticado() async {
    final credenciales = _credenciales;
    if (credenciales == null) return null;
    if (_cliente != null) return _cliente;
    try {
      _cliente = await clientViaServiceAccount(credenciales, const [_scope]);
      return _cliente;
    } catch (e) {
      // Sin red o credencial inválida: se reintenta en el próximo envío.
      if (kDebugMode) {
        debugPrint('FCM: no se pudo obtener el token OAuth2.');
      }
      return null;
    }
  }
}

enum _RolPush { ninguno, cuidador, paciente }
