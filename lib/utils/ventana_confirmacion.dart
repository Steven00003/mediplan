/// Regla pura de la ventana de confirmación de una toma.
///
/// Es la misma que usa la apertura automática de la alarma en
/// `medicamentos_proximos_screen.dart`: una dosis está "a punto de vencerse"
/// cuando su hora programada ya pasó hace hasta 5 minutos o vence dentro de
/// los próximos 2 minutos.
library;

/// `true` cuando [horaProgramada] está dentro de la ventana de confirmación
/// respecto a [ahora].
bool estaEnVentanaConfirmacion(DateTime horaProgramada, DateTime ahora) {
  final diferencia = horaProgramada.difference(ahora);
  return diferencia.inSeconds <= 120 && diferencia.inSeconds >= -300;
}
