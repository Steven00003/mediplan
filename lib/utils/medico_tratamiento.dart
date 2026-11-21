import '../models/tratamiento.dart';

/// Resuelve el UID del médico que recetó un tratamiento.
///
/// Los tratamientos nuevos guardan `recetadoPorId`. Los antiguos no lo tienen,
/// así que se respalda en el `cuidadorId` del paciente.
String? idMedicoRecetador(Tratamiento tratamiento, String? cuidadorIdPaciente) {
  final propio = tratamiento.recetadoPorId?.trim() ?? '';
  if (propio.isNotEmpty) return propio;
  final cuidador = cuidadorIdPaciente?.trim() ?? '';
  return cuidador.isEmpty ? null : cuidador;
}
