import 'ventana_alarmas.dart';

/// Alarma que Android tiene programada actualmente.
///
/// [hora] puede ser `null` si no hay metadatos ni forma de reconstruirla. En
/// ese caso se considera no protegida y se puede cancelar si sobra.
class AlarmaActual {
  final int id;
  final DateTime? hora;

  const AlarmaActual({required this.id, this.hora});
}

/// Diferencia entre la ventana deseada y la realmente programada.
class PlanRearme {
  final List<int> cancelar;
  final List<OcurrenciaAlarma> programar;
  final List<OcurrenciaAlarma> conservar;

  const PlanRearme({
    required this.cancelar,
    required this.programar,
    required this.conservar,
  });

  bool get vacio => cancelar.isEmpty && programar.isEmpty;
}

/// Cálculo puro del rearme incremental.
class CalculadoraRearme {
  const CalculadoraRearme._();

  /// No se toca una alarma que vaya a sonar en menos de este margen.
  static const Duration margenInminente = Duration(seconds: 90);

  /// Tampoco se toca una que haya disparado hace menos de este tiempo.
  static const Duration margenRecienDisparada = Duration(minutes: 2);

  /// Calcula qué cancelar, qué programar y qué dejar intacto.
  ///
  /// - Una ocurrencia deseada que no está programada se programa, aunque sea
  ///   inminente: no hay nada que proteger y es la única forma de que suene.
  /// - Una ocurrencia que coincide por id y hora se conserva.
  /// - Una alarma sobrante se cancela solo si no está protegida por los
  ///   márgenes de [margenInminente] o [margenRecienDisparada].
  /// - Si un id coincide pero la hora no, se reprograma salvo que esté
  ///   protegido; en ese caso se deja como está para no interrumpirla.
  static PlanRearme calcular({
    required List<OcurrenciaAlarma> deseadas,
    required List<AlarmaActual> actuales,
    required DateTime ahora,
  }) {
    final deseadasPorId = <int, OcurrenciaAlarma>{};
    for (final ocurrencia in deseadas) {
      deseadasPorId.putIfAbsent(ocurrencia.id, () => ocurrencia);
    }
    final actualesPorId = <int, AlarmaActual>{};
    for (final actual in actuales) {
      actualesPorId.putIfAbsent(actual.id, () => actual);
    }

    final cancelar = <int>[];
    final programar = <OcurrenciaAlarma>[];
    final conservar = <OcurrenciaAlarma>[];

    for (final ocurrencia in deseadasPorId.values) {
      final actual = actualesPorId[ocurrencia.id];
      if (actual == null) {
        programar.add(ocurrencia);
        continue;
      }
      if (actual.hora == null ||
          _mismaHora(actual.hora!, ocurrencia.horaProgramada)) {
        conservar.add(ocurrencia);
        continue;
      }
      if (protegida(actual.hora, ahora) ||
          protegida(ocurrencia.horaProgramada, ahora)) {
        conservar.add(ocurrencia);
        continue;
      }
      cancelar.add(actual.id);
      programar.add(ocurrencia);
    }

    for (final actual in actualesPorId.values) {
      if (deseadasPorId.containsKey(actual.id)) continue;
      if (protegida(actual.hora, ahora)) continue;
      cancelar.add(actual.id);
    }

    return PlanRearme(
      cancelar: cancelar,
      programar: programar,
      conservar: conservar,
    );
  }

  /// Si [hora] está demasiado cerca para cancelarla o reprogramarla.
  static bool protegida(DateTime? hora, DateTime ahora) {
    if (hora == null) return false;
    final diferencia = hora.difference(ahora);
    if (diferencia >= Duration.zero && diferencia < margenInminente) {
      return true;
    }
    if (diferencia < Duration.zero && -diferencia < margenRecienDisparada) {
      return true;
    }
    return false;
  }

  static bool _mismaHora(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }
}
