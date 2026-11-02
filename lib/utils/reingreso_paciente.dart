/// Vinculación que este dispositivo recuerda aunque el paciente haya salido
/// del modo paciente.
///
/// Es distinta del flag de "paciente activo": al salir se borra el flag activo,
/// pero esta ficha se conserva para ofrecer "Continuar como paciente" sin pedir
/// el código otra vez. Solo se borra cuando el cuidador desvincula, cuando el
/// servidor ya no reconoce este UID o cuando el usuario pulsa "Usar otro
/// código".
class VinculacionRecordada {
  final String pacienteId;
  final String codigo;
  final String nombre;

  const VinculacionRecordada({
    required this.pacienteId,
    required this.codigo,
    required this.nombre,
  });

  /// El id es lo único imprescindible: el reingreso se valida contra Firestore
  /// con ese id. El código se guarda para poder mostrarlo o migrar flujos
  /// antiguos, y el nombre solo para la interfaz.
  bool get esValida => pacienteId.trim().isNotEmpty;
}

/// Decide si la pantalla de selección de rol debe ofrecer el botón grande
/// "Continuar como paciente".
///
/// Es lógica pura para poder probarla sin Firebase ni SharedPreferences.
bool debeOfrecerContinuarComoPaciente({
  required VinculacionRecordada? recordada,
  required bool pacienteActivo,
  required bool sesionCuidador,
}) {
  if (pacienteActivo || sesionCuidador) return false;
  return recordada?.esValida ?? false;
}

/// Resultado de intentar reingresar con la vinculación recordada.
enum ResultadoReingresoPaciente {
  /// Se validó contra el servidor y el paciente quedó activo.
  exito,

  /// No hay ninguna vinculación guardada (o le falta el pacienteId).
  sinVinculacionRecordada,

  /// El servidor ya no tiene ese paciente vinculado a este UID. La
  /// vinculación recordada se borró.
  noCoincide,

  /// No se pudo consultar el servidor (red, timeout, etc.). La vinculación
  /// recordada se conserva para reintentar.
  errorRed,
}
