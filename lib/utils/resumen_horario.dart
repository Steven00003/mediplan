import 'package:flutter/foundation.dart';

import '../models/tratamiento.dart';

/// Resumen del horario de un tratamiento para mostrarlo en una tarjeta:
/// devuelve las horas y, aparte, la línea de días.
///
/// - Si **todos los horarios comparten exactamente los mismos días** (el caso
///   común) devuelve las horas sueltas y los días en una segunda línea, para no
///   repetir el mismo "Lun · Mié · Vie" en cada hora.
/// - Si difieren, los días van junto a la hora que los tiene:
///   `08:00 (Lun · Mié · Vie) / 20:00 (Mar · Jue)`, y la segunda línea queda
///   vacía. Un horario diario (los 7) se queda solo con su hora.
///
/// El orden de [HorarioDia.dias] no importa: se comparan como conjuntos.
(String, String) resumenHorario(Tratamiento t) {
  final compartenDias = t.horarios.length < 2 ||
      t.horarios
          .map((h) => h.dias.toSet())
          .every((d) => setEquals(d, t.horarios.first.dias.toSet()));

  if (compartenDias) {
    final dias =
        t.horarios.isEmpty ? '' : _diasLegibles(t.horarios.first.dias);
    return (t.horarios.map((h) => h.hora).join(' / '), dias);
  }
  final horas = t.horarios.map((h) {
    final dias = _diasLegibles(h.dias);
    return dias.isEmpty ? h.hora : '${h.hora} ($dias)';
  }).join(' / ');
  return (horas, '');
}

/// Días ISO de un horario como texto: "Lun · Mié · Vie".
///
/// Devuelve vacío si aplica los 7 días (o no tiene días), porque en ese caso
/// el rótulo no aporta nada.
String _diasLegibles(Iterable<int> dias) {
  const nombres = {
    1: 'Lun',
    2: 'Mar',
    3: 'Mié',
    4: 'Jue',
    5: 'Vie',
    6: 'Sáb',
    7: 'Dom',
  };
  final unicos = dias.toSet();
  if (unicos.length == 7 || unicos.isEmpty) return '';
  final ordenados = unicos.toList()..sort();
  return ordenados.map((d) => nombres[d] ?? '?').join(' · ');
}
