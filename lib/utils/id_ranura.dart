import 'hash_estable.dart';

/// Id determinista de una ranura de toma.
///
/// La identidad de una ranura es `(tratamientoId, horaProgramada)`. El id se
/// deriva de esa clave para que confirmar y marcar una toma como olvidada
/// escriban **el mismo documento** si llegaran a competir por la misma dosis.
///
/// Se mantiene exactamente el esquema que ya usaba `OmitidasService` (prefijo
/// `omitida|`) para no romper los ids de las tomas olvidadas que ya existen.
/// `posponer` no usa este id: posponer no cierra la ranura.
String idDocumentoDeRanura(String tratamientoId, DateTime horaProgramada) {
  return hashEstable(
    'omitida|$tratamientoId|${horaProgramada.millisecondsSinceEpoch}',
  ).toString();
}
