/// Divide [elementos] en lotes de como máximo [tamano] elementos.
///
/// Firestore limita un batch a 500 operaciones; el borrado de pacientes usa
/// 400 para dejar margen a futuras operaciones auxiliares.
List<List<T>> partirEnLotes<T>(List<T> elementos, int tamano) {
  if (tamano <= 0) {
    throw ArgumentError.value(tamano, 'tamano', 'Debe ser mayor que cero');
  }
  final lotes = <List<T>>[];
  for (var i = 0; i < elementos.length; i += tamano) {
    final fin = i + tamano > elementos.length ? elementos.length : i + tamano;
    lotes.add(elementos.sublist(i, fin));
  }
  return lotes;
}
