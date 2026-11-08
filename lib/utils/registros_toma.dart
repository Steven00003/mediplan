import '../models/registro_toma.dart';

/// Reglas puras para tratar los registros de una ranura de toma.
///
/// Una ranura es `(tratamientoId, horaProgramada)`. En datos viejos puede haber
/// más de un documento para la misma ranura (cada "YA" creaba un `.add()`), así
/// que el historial y las estadísticas deben quedarse con **uno** solo. El
/// criterio es conservar la primera confirmación; una toma pospuesta nunca
/// cierra la ranura y un estado terminal siempre gana.
class RegistrosToma {
  const RegistrosToma._();

  /// Clave estable de una ranura, equivalente a `RanuraToma.clave`.
  static String claveDeRanura(
    String tratamientoId,
    DateTime horaProgramada,
  ) =>
      '$tratamientoId|${horaProgramada.millisecondsSinceEpoch}';

  static String clave(RegistroToma registro) =>
      claveDeRanura(registro.tratamientoId, registro.horaProgramada);

  /// ¿El estado cierra la ranura? `pospuesta` y `pendiente` no.
  static bool esFinal(EstadoToma estado) => estado.esTerminal;

  /// El registro que mejor representa una ranura concreta.
  ///
  /// Devuelve `null` si no hay ningún registro para esa ranura. Si hay varios,
  /// prioriza un estado terminal y, entre terminales, la primera confirmación.
  /// Si solo hay no terminales, prioriza `pospuesta` sobre `pendiente`.
  static RegistroToma? mejorDeRanura(
    Iterable<RegistroToma> registros, {
    required String tratamientoId,
    required DateTime horaProgramada,
  }) {
    RegistroToma? mejor;
    for (final r in registros) {
      if (r.tratamientoId != tratamientoId) continue;
      if (r.horaProgramada.millisecondsSinceEpoch !=
          horaProgramada.millisecondsSinceEpoch) {
        continue;
      }
      if (mejor == null || _esMejor(r, mejor)) mejor = r;
    }
    return mejor;
  }

  /// El registro final de una ranura, o `null` si sigue abierta.
  static RegistroToma? finalDeRanura(
    Iterable<RegistroToma> registros, {
    required String tratamientoId,
    required DateTime horaProgramada,
  }) {
    final mejor = mejorDeRanura(
      registros,
      tratamientoId: tratamientoId,
      horaProgramada: horaProgramada,
    );
    return mejor != null && mejor.estado.esTerminal ? mejor : null;
  }

  /// Deja un solo registro por ranura, conservando la primera confirmación.
  ///
  /// El orden de salida es el de la primera aparición de cada ranura, así que
  /// quien necesite ordenar lo hace después (historial) o indexa por clave
  /// (estadísticas).
  static List<RegistroToma> deduplicarPorRanura(
    Iterable<RegistroToma> registros,
  ) {
    final porClave = <String, RegistroToma>{};
    for (final r in registros) {
      final k = clave(r);
      final actual = porClave[k];
      if (actual == null || _esMejor(r, actual)) porClave[k] = r;
    }
    return porClave.values.toList();
  }

  /// `true` si [candidato] debe reemplazar a [actual] para la misma ranura.
  static bool _esMejor(RegistroToma candidato, RegistroToma actual) {
    // Un estado terminal (tomó/tardó/olvidó) cierra la ranura; pospuesta no.
    if (candidato.estado.esTerminal != actual.estado.esTerminal) {
      return candidato.estado.esTerminal;
    }

    // Entre dos registros del mismo "nivel", la primera confirmación manda.
    // `olvidada` no tiene hora de confirmación: si compite con una confirmada,
    // la confirmada gana; si compiten dos olvidadas, se conserva la primera.
    final c = candidato.horaConfirmacion;
    final a = actual.horaConfirmacion;
    if (c == null && a == null) return false;
    if (c == null) return false;
    if (a == null) return true;
    return c.isBefore(a);
  }
}
