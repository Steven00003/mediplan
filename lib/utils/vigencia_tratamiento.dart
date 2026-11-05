import '../models/tratamiento.dart';

/// Cálculos puros de vigencia de un tratamiento.
///
/// La fecha de inicio y la duración son fechas locales sin hora. La fecha de fin
/// es **inclusiva**: un tratamiento de 3 días que empieza el lunes termina el
/// miércoles. Toda la comparación se hace por día de calendario, nunca por
/// instantes, para que el cambio de día ocurra a medianoche local.
class VigenciaTratamiento {
  const VigenciaTratamiento._();

  /// Último día del tratamiento, o `null` si es continuo o tiene inicio
  /// desconocido (documentos antiguos sin `fechaInicio`).
  static DateTime? fechaFin(Tratamiento tratamiento) {
    final inicio = tratamiento.fechaInicio;
    final dias = tratamiento.duracionDias;
    if (inicio == null || dias == null) return null;
    // El constructor con día fuera de rango normaliza el mes/año y mantiene la
    // medianoche local, sin sumar 24 h absolutas (eso fallaría en cambios de
    // horario de verano).
    return DateTime(inicio.year, inicio.month, inicio.day + dias - 1);
  }

  /// Si el tratamiento cuenta para [ahora].
  ///
  /// Continuo o con inicio desconocido => vigente. Con fecha y duración => solo
  /// entre el primer y el último día, ambos incluidos.
  static bool estaVigente(Tratamiento tratamiento, DateTime ahora) {
    final inicio = tratamiento.fechaInicio;
    final fin = fechaFin(tratamiento);
    if (inicio == null || fin == null) return true;
    final hoy = _claveDia(ahora);
    return hoy >= _claveDia(inicio) && hoy <= _claveDia(fin);
  }

  /// Días de calendario que quedan, contando hoy.
  ///
  /// El último día devuelve `1`; el día siguiente devuelve `0` o un negativo.
  /// `null` cuando no hay fecha de fin (continuo o inicio desconocido).
  static int? diasRestantes(Tratamiento tratamiento, DateTime ahora) {
    final fin = fechaFin(tratamiento);
    if (fin == null) return null;
    return _claveDia(fin) - _claveDia(ahora) + 1;
  }

  /// Texto para el paciente, o `null` si no hay información de vigencia.
  static String? textoParaPaciente(Tratamiento tratamiento, DateTime ahora) {
    final dias = diasRestantes(tratamiento, ahora);
    if (dias == null) return null;
    if (dias <= 0) return 'Tratamiento terminado';
    if (dias == 1) return 'Hoy es el último día';
    return 'Te quedan $dias días';
  }

  /// Día de calendario como entero comparable, inmune a zonas horarias y DST.
  static int _claveDia(DateTime fecha) =>
      DateTime.utc(fecha.year, fecha.month, fecha.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
