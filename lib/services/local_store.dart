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

  static Future<void> guardarPacienteVinculado(String pacienteId, String nombre) async {
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

  static String _generarId() {
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return 'disp-$rnd';
  }
}
