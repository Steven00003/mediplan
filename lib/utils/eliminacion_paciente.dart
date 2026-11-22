/// Pasos del borrado de un paciente, después de leer su documento.
///
/// La notificación al celular va **después** del borrado del documento del
/// paciente, porque solo tiene sentido si el borrado terminó con éxito. Así se
/// evita que el teléfono cancele alarmas mientras el perfil todavía existe.
enum PasoEliminacionPaciente {
  tratamientos,
  registrosToma,
  vinculo,
  paciente,
  notificarPaciente,
}

/// Orden puro de los pasos, para poder verificarlo sin Firestore.
///
/// `tieneVinculo` indica que el paciente tiene código no vacío. `notificarPaciente`
/// indica que había dispositivo vinculado y token FCM guardado en memoria.
List<PasoEliminacionPaciente> ordenEliminacionPaciente({
  required bool tieneVinculo,
  required bool notificarPaciente,
}) {
  return <PasoEliminacionPaciente>[
    PasoEliminacionPaciente.tratamientos,
    PasoEliminacionPaciente.registrosToma,
    if (tieneVinculo) PasoEliminacionPaciente.vinculo,
    PasoEliminacionPaciente.paciente,
    if (notificarPaciente) PasoEliminacionPaciente.notificarPaciente,
  ];
}
