/// Guard simple para que dos rearmes de alarmas no se solapen.
///
/// Es puro y sin dependencias para poder probar la semántica sin el plugin:
/// la primera entrada gana, las siguientes se rechazan hasta llamar a [salir].
class GuardRearme {
  bool _activo = false;

  bool get activo => _activo;

  /// Intenta entrar. Devuelve `false` si ya había un rearme en curso.
  bool entrar() {
    if (_activo) return false;
    _activo = true;
    return true;
  }

  /// Libera el guard. Es idempotente.
  void salir() {
    _activo = false;
  }
}
