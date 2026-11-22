/// Compara el nombre que escribe el doctor con el nombre real del paciente.
///
/// Se ignoran los espacios de los extremos, pero no las mayúsculas ni los
/// espacios internos: la confirmación debe ser exactamente el nombre mostrado.
bool nombreConfirmaEliminacion({
  required String nombrePaciente,
  required String textoEscrito,
}) {
  final esperado = nombrePaciente.trim();
  if (esperado.isEmpty) return false;
  return textoEscrito.trim() == esperado;
}
