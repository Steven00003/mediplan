import '../models/registro_toma.dart';

/// Reglas puras del historial de un medicamento en la pantalla de alarma.
///
/// La consulta de Firestore ya filtra por tratamiento, ventana de días y
/// `horaProgramada <= ahora`, y pide las más recientes. Esta función repite el
/// filtro de forma defensiva y, sobre todo, fija en un solo lugar el orden
/// descendente y el límite, de modo que se pueda probar sin Firebase.
class HistorialTomas {
  const HistorialTomas._();

  /// Las [limite] tomas más recientes de los últimos [dias] días, de más
  /// reciente a más antigua.
  ///
  /// Se excluyen las tomas futuras: la alarma puede abrirse antes de la hora
  /// programada (ventana de -5 min) y una toma de hoy más tarde no debe
  /// aparecer como si ya hubiera ocurrido.
  static List<RegistroToma> recientes(
    Iterable<RegistroToma> registros, {
    required DateTime ahora,
    int dias = 7,
    int limite = 10,
  }) {
    if (dias <= 0 || limite <= 0) return const <RegistroToma>[];

    // Ventana de [dias] días de calendario, incluido hoy. Con 7 días, el
    // límite inferior es la medianoche de hace 6 días.
    final inicio = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
    ).subtract(Duration(days: dias - 1));

    final filtrados = registros.where((r) {
      final hora = r.horaProgramada;
      return !hora.isAfter(ahora) && !hora.isBefore(inicio);
    }).toList()..sort((a, b) => b.horaProgramada.compareTo(a.horaProgramada));

    return filtrados.take(limite).toList();
  }
}
