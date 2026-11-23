/// Asistente de permisos del paciente: pasos que aplican segun Android.
library;

enum PasoPermisoPaciente {
  notificaciones,
  alarmasExactas,
  pantallaCompleta,
  canalAlarmas,
  bateria,
  inicioAutomatico,
}

extension PasoPermisoPacienteTexto on PasoPermisoPaciente {
  String get titulo => switch (this) {
    PasoPermisoPaciente.notificaciones => 'Notificaciones',
    PasoPermisoPaciente.alarmasExactas => 'Alarmas exactas',
    PasoPermisoPaciente.pantallaCompleta => 'Pantalla completa',
    PasoPermisoPaciente.canalAlarmas => 'Sonido de alarmas',
    PasoPermisoPaciente.bateria => 'Bateria',
    PasoPermisoPaciente.inicioAutomatico => 'Inicio automatico',
  };

  String get explicacion => switch (this) {
    PasoPermisoPaciente.notificaciones =>
      'Para que te avisemos cuando toca una toma.',
    PasoPermisoPaciente.alarmasExactas =>
      'Para que la alarma suene a la hora exacta que programaste.',
    PasoPermisoPaciente.pantallaCompleta =>
      'Para que la alarma se abra aunque el telefono este bloqueado.',
    PasoPermisoPaciente.canalAlarmas =>
      'Para que las alarmas suenen y vibren cuando toque.',
    PasoPermisoPaciente.bateria =>
      'Para que Android no retrase tus alarmas al ahorrar bateria.',
    PasoPermisoPaciente.inicioAutomatico =>
      'Para que MediPlan vuelva a arrancar despues de reiniciar.',
  };
}

bool pasoAplica(PasoPermisoPaciente paso, int? sdkInt) {
  return switch (paso) {
    PasoPermisoPaciente.notificaciones => true,
    PasoPermisoPaciente.alarmasExactas => sdkInt != null && sdkInt >= 31,
    PasoPermisoPaciente.pantallaCompleta => sdkInt != null && sdkInt >= 34,
    PasoPermisoPaciente.canalAlarmas => sdkInt != null && sdkInt >= 26,
    PasoPermisoPaciente.bateria => sdkInt != null && sdkInt >= 23,
    PasoPermisoPaciente.inicioAutomatico => true,
  };
}

List<PasoPermisoPaciente> pasosAplicables(int? sdkInt) {
  return PasoPermisoPaciente.values
      .where((paso) => pasoAplica(paso, sdkInt))
      .toList(growable: false);
}

enum EstadoPasoPermiso { concedido, pendiente, noAplica }

EstadoPasoPermiso estadoDePaso(
  PasoPermisoPaciente paso,
  int? sdkInt,
  bool? concedido,
) {
  if (!pasoAplica(paso, sdkInt)) return EstadoPasoPermiso.noAplica;
  return concedido == true
      ? EstadoPasoPermiso.concedido
      : EstadoPasoPermiso.pendiente;
}

class ResumenPermisos {
  final int listos;
  final int pendientes;
  final int total;

  const ResumenPermisos({
    required this.listos,
    required this.pendientes,
    required this.total,
  });

  bool get todoListo => total > 0 && pendientes == 0;
}

ResumenPermisos resumenPasos(List<EstadoPasoPermiso> estados) {
  final aplicables = estados
      .where((e) => e != EstadoPasoPermiso.noAplica)
      .toList();
  final listos = aplicables
      .where((e) => e == EstadoPasoPermiso.concedido)
      .length;
  final pendientes = aplicables.length - listos;
  return ResumenPermisos(
    listos: listos,
    pendientes: pendientes,
    total: aplicables.length,
  );
}
