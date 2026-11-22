/// Decide si este teléfono debe olvidar al paciente porque su documento ya no
/// existe o porque la lectura fue rechazada por permisos.
///
/// Un error de red no entra aquí: el paciente debe seguir usando sus alarmas y
/// datos locales hasta que el servidor dé una señal definitiva.
bool debeOlvidarPacientePorLectura({
  required bool existePaciente,
  required bool permisoDenegado,
}) {
  return !existePaciente || permisoDenegado;
}
