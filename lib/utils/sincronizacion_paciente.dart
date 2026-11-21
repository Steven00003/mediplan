/// Lógica pura del push de sincronización cuidador → paciente.
///
/// No importa Flutter, Firebase ni los plugins: recibe datos ya leídos por los
/// servicios y decide si un mensaje es válido, si debe procesarse en este
/// teléfono y cuándo vence el debounce que agrupa varios cambios seguidos.
library;

/// Tiempo que se agrupan los cambios de tratamientos antes de enviar el push.
const Duration debounceSincronizacionPaciente = Duration(seconds: 10);

/// Tipo de mensaje FCM de sincronización. Es el único dato de control que se
/// acepta además del id del paciente.
const String tipoMensajeSincronizacion = 'sync';

/// Id máximo aceptado para un documento de paciente.
const int _maxLongitudPacienteId = 128;

/// Extrae el `pacienteId` de un mensaje FCM de sincronización.
///
/// Devuelve `null` si el mensaje no es del tipo esperado o el id falta / es
/// inválido. No se confía en ningún otro campo del mensaje.
String? pacienteIdDesdeMensajeSincronizacion(Map<String, dynamic> datos) {
  final tipo = (datos['tipo'] as String?)?.trim();
  if (tipo != tipoMensajeSincronizacion) return null;

  final pacienteId = (datos['pacienteId'] as String?)?.trim() ?? '';
  if (pacienteId.isEmpty || pacienteId.length > _maxLongitudPacienteId) {
    return null;
  }
  return pacienteId;
}

/// ¿El mensaje tiene la forma mínima de un aviso de sincronización?
bool esMensajeSincronizacionValido(Map<String, dynamic> datos) {
  return pacienteIdDesdeMensajeSincronizacion(datos) != null;
}

/// Decide si este teléfono debe procesar el mensaje.
///
/// Deben coincidir el paciente del mensaje con la vinculación local, el UID
/// actual con `dispositivoVinculadoId` y la sesión debe ser anónima (paciente).
/// Cualquier dato ausente se trata como no procesable: es preferible no rearmar
/// antes que hacerlo en el teléfono equivocado.
bool debeProcesarSincronizacion({
  required String? pacienteIdMensaje,
  required String? pacienteIdLocal,
  required String? uidActual,
  required String? dispositivoVinculadoId,
  required bool sesionAnonima,
}) {
  final mensaje = pacienteIdMensaje?.trim() ?? '';
  final local = pacienteIdLocal?.trim() ?? '';
  final uid = uidActual?.trim() ?? '';
  final dispositivo = dispositivoVinculadoId?.trim() ?? '';

  if (!sesionAnonima) return false;
  if (mensaje.isEmpty || local.isEmpty || uid.isEmpty || dispositivo.isEmpty) {
    return false;
  }
  return mensaje == local && uid == dispositivo;
}

/// Estado puro de un debounce con reinicio (trailing).
///
/// El servicio real usa un [Timer], pero la decisión de cuándo vence se prueba
/// aquí sin relojes ni plataforma. Cada llamada a [registrar] invalida la
/// generación anterior, de modo que el envío ocurre diez segundos después del
/// último cambio y no del primero.
class DebounceSincronizacion {
  final Duration espera;
  final Map<String, DateTime> _ultimaSolicitud = {};
  final Map<String, int> _generacion = {};

  DebounceSincronizacion({this.espera = debounceSincronizacionPaciente});

  /// Registra un cambio y devuelve su generación.
  int registrar(String clave, DateTime ahora) {
    _ultimaSolicitud[clave] = ahora;
    final siguiente = (_generacion[clave] ?? 0) + 1;
    _generacion[clave] = siguiente;
    return siguiente;
  }

  /// Tiempo restante para enviar, o `null` si esa generación ya fue reemplazada.
  Duration? retrasoPendiente(String clave, int generacion, DateTime ahora) {
    if (_generacion[clave] != generacion) return null;
    final ultima = _ultimaSolicitud[clave];
    if (ultima == null) return null;

    final restante = espera - ahora.difference(ultima);
    return restante.isNegative ? Duration.zero : restante;
  }

  /// `true` cuando ya pasó [espera] desde el último cambio de esta generación.
  bool debeEnviar(String clave, int generacion, DateTime ahora) {
    return retrasoPendiente(clave, generacion, ahora) == Duration.zero;
  }

  /// Limpia el estado de una generación ya enviada.
  void limpiar(String clave, int generacion) {
    if (_generacion[clave] != generacion) return;
    // Se conserva la generación para que las nuevas no reutilicen un número
    // ya enviado; solo se borra el instante pendiente.
    _ultimaSolicitud.remove(clave);
  }
}
