/// Estado de un código de vinculación según su fecha de expiración.
enum EstadoCodigoVinculacion { vigente, vencido, sinVencimiento }

/// Calcula si un código está vigente, vencido o no tiene fecha de expiración.
///
/// Un código se considera vencido justo en el instante `expiraEn` (el límite es
/// exclusivo), igual que la regla de Firestore, que exige `expiraEn > request.time`.
/// Un `null` representa un vínculo antiguo sin fecha y se mantiene vigente por
/// compatibilidad.
EstadoCodigoVinculacion estadoDelCodigo(DateTime? expiraEn, DateTime ahora) {
  if (expiraEn == null) return EstadoCodigoVinculacion.sinVencimiento;
  return ahora.isBefore(expiraEn)
      ? EstadoCodigoVinculacion.vigente
      : EstadoCodigoVinculacion.vencido;
}

/// Texto para mostrar al cuidador en el detalle del paciente.
String textoVencimientoCodigo(DateTime? expiraEn, DateTime ahora) {
  final estado = estadoDelCodigo(expiraEn, ahora);
  return switch (estado) {
    EstadoCodigoVinculacion.vencido => 'Código vencido',
    EstadoCodigoVinculacion.sinVencimiento => 'Sin vencimiento',
    EstadoCodigoVinculacion.vigente =>
      'Vence el ${_fecha(expiraEn!)} a las ${_hora(expiraEn)}',
  };
}

String _fecha(DateTime fecha) {
  return '${_dosDigitos(fecha.day)}/${_dosDigitos(fecha.month)}';
}

String _hora(DateTime fecha) {
  return '${_dosDigitos(fecha.hour)}:${_dosDigitos(fecha.minute)}';
}

String _dosDigitos(int valor) => valor.toString().padLeft(2, '0');
