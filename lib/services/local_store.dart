import 'package:shared_preferences/shared_preferences.dart';

import '../utils/reingreso_paciente.dart';

/// Almacenamiento local persistente del dispositivo del paciente.
///
/// El vínculo dispositivo-paciente debe sobrevivir reinicios del teléfono,
/// por lo que NO depende de la sesión de Firebase. Se guarda como un token
/// local propio en `shared_preferences`.
class LocalStore {
  static const _kDispositivoId = 'dispositivo_id';
  static const _kPacienteId = 'paciente_id';
  static const _kPacienteNombre = 'paciente_nombre';
  static const _kPantallaCompletaPreguntada = 'pantalla_completa_preguntada';

  // Vinculación recordada: sobrevive a la salida del modo paciente para poder
  // ofrecer "Continuar como paciente" sin volver a escribir el código. Es una
  // clave independiente del flag de paciente activo (`paciente_id`).
  static const _kUltimoPacienteId = 'ultima_vinculacion_paciente_id';
  static const _kUltimoCodigo = 'ultima_vinculacion_codigo';
  static const _kUltimoNombre = 'ultima_vinculacion_nombre';

  // Migración de alarmas que versiones anteriores pudieron dejar programadas en
  // el teléfono de un cuidador. La versión evita repetir la limpieza en cada
  // login; `pendiente_reprogramar` avisa al paciente de que debe volver a
  // programar sus alarmas la próxima vez que entre en este teléfono.
  static const _kVersionMigracionAlarmas = 'migracion_alarmas_version';
  static const _kPendienteReprogramarAlarmas =
      'migracion_alarmas_pendiente_reprogramar';

  /// Versión actual de la migración de alarmas.
  static const int versionMigracionAlarmas = 1;

  // Último reporte de `estadoDispositivo`. Sirve para no escribir Firestore más
  // de una vez cada 30 min si los valores del celular no cambiaron.
  static const _kEstadoDispositivoUltimoEnvio =
      'estado_dispositivo_ultimo_envio';
  static const _kEstadoDispositivoFirma = 'estado_dispositivo_firma';

  // Aviso único del primer arranque como paciente y último error de
  // sincronización local que se muestra en "Comprobar mi celular".
  static const _kAvisoPermisosCelularMostrado =
      'aviso_permisos_celular_mostrado';
  static const _kUltimoErrorSincronizacion = 'ultimo_error_sincronizacion';
  static const _kMensajeSeleccionRol = 'mensaje_seleccion_rol';

  /// Genera (la primera vez) o recupera el identificador estable de este
  /// dispositivo. Se usa como `dispositivoVinculadoId` en Firestore.
  static Future<String> getDispositivoId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDispositivoId);
    if (id == null || id.isEmpty) {
      id = _generarId();
      await prefs.setString(_kDispositivoId, id);
    }
    return id;
  }

  static Future<void> guardarPacienteVinculado(
    String pacienteId,
    String nombre,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPacienteId, pacienteId);
    await prefs.setString(_kPacienteNombre, nombre);
  }

  static Future<String?> getPacienteVinculadoId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPacienteId);
  }

  static Future<String?> getPacienteVinculadoNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPacienteNombre);
  }

  static Future<void> limpiarPacienteVinculado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPacienteId);
    await prefs.remove(_kPacienteNombre);
  }

  /// Guarda la última vinculación para ofrecer "Continuar como paciente".
  ///
  /// No toca el flag de paciente activo: al salir se borra ese flag, pero esta
  /// ficha se conserva.
  static Future<void> guardarUltimaVinculacion({
    required String pacienteId,
    required String codigo,
    required String nombre,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUltimoPacienteId, pacienteId);
    await prefs.setString(_kUltimoCodigo, codigo.trim().toUpperCase());
    await prefs.setString(_kUltimoNombre, nombre);
  }

  static Future<VinculacionRecordada?> getUltimaVinculacion() async {
    final prefs = await SharedPreferences.getInstance();
    final pacienteId = prefs.getString(_kUltimoPacienteId);
    if (pacienteId == null || pacienteId.trim().isEmpty) return null;
    return VinculacionRecordada(
      pacienteId: pacienteId,
      codigo: prefs.getString(_kUltimoCodigo) ?? '',
      nombre: prefs.getString(_kUltimoNombre) ?? '',
    );
  }

  static Future<void> limpiarUltimaVinculacion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUltimoPacienteId);
    await prefs.remove(_kUltimoCodigo);
    await prefs.remove(_kUltimoNombre);
  }

  /// ¿Ya se mostró el diálogo del permiso de pantalla completa?
  ///
  /// Es un aviso único por instalación: si el paciente lo deniega, no se le
  /// vuelve a interrumpir en cada apertura. Puede activarlo después desde los
  /// Ajustes de Android.
  static Future<bool> getPantallaCompletaPreguntada() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPantallaCompletaPreguntada) ?? false;
  }

  static Future<void> marcarPantallaCompletaPreguntada() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPantallaCompletaPreguntada, true);
  }

  /// Versión de la migración de alarmas ya aplicada en este dispositivo.
  static Future<int> getVersionMigracionAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kVersionMigracionAlarmas) ?? 0;
  }

  static Future<void> guardarVersionMigracionAlarmas(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kVersionMigracionAlarmas, version);
  }

  /// El teléfono dejó de ser paciente y debe reprogramar sus alarmas cuando
  /// vuelva a entrar como paciente.
  static Future<bool> getPendienteReprogramarAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPendienteReprogramarAlarmas) ?? false;
  }

  static Future<void> marcarPendienteReprogramarAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPendienteReprogramarAlarmas, true);
  }

  static Future<void> limpiarPendienteReprogramarAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendienteReprogramarAlarmas);
  }

  static Future<DateTime?> getUltimoEnvioEstadoDispositivo() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kEstadoDispositivoUltimoEnvio);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<String?> getFirmaEstadoDispositivo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEstadoDispositivoFirma);
  }

  static Future<void> guardarEnvioEstadoDispositivo({
    required DateTime fecha,
    required String firma,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kEstadoDispositivoUltimoEnvio,
      fecha.millisecondsSinceEpoch,
    );
    await prefs.setString(_kEstadoDispositivoFirma, firma);
  }

  /// ¿Ya se mostró el aviso amable de permisos al entrar como paciente?
  ///
  /// Es único por instalación: si el paciente lo descarta, puede volver a la
  /// pantalla desde "Comprobar mi celular" cuando quiera.
  static Future<bool> getAvisoPermisosCelularMostrado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAvisoPermisosCelularMostrado) ?? false;
  }

  static Future<void> marcarAvisoPermisosCelularMostrado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAvisoPermisosCelularMostrado, true);
  }

  /// Último error de sincronización local, ya traducido a texto para el
  /// paciente. Se borra cuando la sincronización vuelve a funcionar.
  static Future<String?> getUltimoErrorSincronizacion() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_kUltimoErrorSincronizacion)?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static Future<void> guardarUltimoErrorSincronizacion(String error) async {
    final limpio = error.trim();
    if (limpio.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final limitado = limpio.length > 240
        ? '${limpio.substring(0, 240)}…'
        : limpio;
    await prefs.setString(_kUltimoErrorSincronizacion, limitado);
  }

  static Future<void> limpiarUltimoErrorSincronizacion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUltimoErrorSincronizacion);
  }

  /// Mensaje de una sola vez para mostrar al volver a la selección de rol.
  static Future<void> guardarMensajeSeleccionRol(String mensaje) async {
    final limpio = mensaje.trim();
    if (limpio.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMensajeSeleccionRol, limpio);
  }

  /// Lee y borra el mensaje pendiente, para que no se repita en cada arranque.
  static Future<String?> tomarMensajeSeleccionRol() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_kMensajeSeleccionRol)?.trim() ?? '';
    await prefs.remove(_kMensajeSeleccionRol);
    return texto.isEmpty ? null : texto;
  }

  static String _generarId() {
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return 'disp-$rnd';
  }
}
