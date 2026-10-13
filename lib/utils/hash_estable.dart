/// Hash polinómico de 31 bits: determinista y estable entre ejecuciones,
/// plataformas y versiones de Dart.
///
/// Existe porque `String.hashCode` no sirve para derivar identificadores
/// persistentes: Dart solo garantiza que sea consistente *dentro de una misma
/// ejecución*, así que un id derivado de él no se puede recalcular al reiniciar
/// la app. Éste sí.
///
/// Se usa para las ids de alarma (`NotificacionesService.idDeAlarma`) y para
/// la id de documento de las tomas olvidadas (`OmitidasService`): en ambos casos
/// el id tiene que poder **recalcularse** más tarde en lugar de guardarse, y en
/// el caso de las olvidadas eso además lo hace idempotente ante reconciliaciones
/// solapadas.
///
/// El resultado se acota a 31 bits para caber en el entero de 32 bits con signo
/// que exigen el plugin de notificaciones y Firestore. El `0` se reserva, así
/// que se devuelve `1` en su lugar.
int hashEstable(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7FFFFFFF;
  }
  return h == 0 ? 1 : h;
}