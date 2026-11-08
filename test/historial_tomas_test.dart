// Pruebas puras del orden y del límite del historial de un medicamento.
//
// No usan Firebase: la consulta real filtra por tratamiento y ventana de días,
// y esta función fija la parte que se puede probar sin red: excluir tomas
// futuras, ordenar de más reciente a más antigua y recortar a 10.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/registro_toma.dart';
import 'package:mediplan/utils/historial_tomas.dart';

RegistroToma _registro(
  String id,
  DateTime hora, {
  DateTime? horaConfirmacion,
}) => RegistroToma(
  id: id,
  tratamientoId: 't1',
  pacienteId: 'p1',
  horaProgramada: hora,
  horaConfirmacion: horaConfirmacion,
  estado: EstadoToma.tomada,
);

void main() {
  final ahora = DateTime(2026, 11, 5, 12);

  group('HistorialTomas.recientes', () {
    test('ordena de más reciente a más antigua y limita a 10', () {
      final registros = [
        for (var i = 0; i < 12; i++)
          _registro('r$i', ahora.subtract(Duration(hours: i + 1))),
        _registro('futura', ahora.add(const Duration(minutes: 1))),
      ];

      final resultado = HistorialTomas.recientes(registros, ahora: ahora);

      expect(resultado, hasLength(10));
      expect(resultado.first.id, 'r0');
      expect(resultado.last.id, 'r9');
      expect(resultado.map((r) => r.id), isNot(contains('futura')));
      expect(
        resultado.map((r) => r.horaProgramada).toList(),
        orderedEquals([
          for (var i = 0; i < 10; i++) ahora.subtract(Duration(hours: i + 1)),
        ]),
      );
    });

    test('deduplica por ranura y conserva la primera confirmación', () {
      final hora = ahora.subtract(const Duration(hours: 2));
      final resultado = HistorialTomas.recientes([
        _registro(
          'segunda',
          hora,
          horaConfirmacion: hora.add(const Duration(minutes: 10)),
        ),
        _registro(
          'primera',
          hora,
          horaConfirmacion: hora.add(const Duration(minutes: 2)),
        ),
      ], ahora: ahora);

      expect(resultado.map((r) => r.id), orderedEquals(['primera']));
    });

    test('excluye tomas futuras aunque estén dentro del rango de días', () {
      final resultado = HistorialTomas.recientes([
        _registro('pasada', ahora.subtract(const Duration(minutes: 5))),
        _registro('futura', ahora.add(const Duration(minutes: 5))),
      ], ahora: ahora);

      expect(resultado.map((r) => r.id), orderedEquals(['pasada']));
    });

    test('la ventana es de 7 días de calendario e incluye el límite', () {
      final resultado = HistorialTomas.recientes([
        _registro('limite', DateTime(2026, 10, 30)),
        _registro('anterior', DateTime(2026, 10, 29, 23, 59)),
        _registro('reciente', ahora.subtract(const Duration(hours: 1))),
      ], ahora: ahora);

      expect(
        resultado.map((r) => r.id),
        orderedEquals(['reciente', 'limite']),
      );
      expect(resultado.map((r) => r.id), isNot(contains('anterior')));
    });

    test('devuelve vacío si no hay tomas', () {
      expect(HistorialTomas.recientes(const [], ahora: ahora), isEmpty);
    });

    test('devuelve vacío si días o límite no son positivos', () {
      final registros = [
        _registro('r1', ahora.subtract(const Duration(hours: 1))),
      ];

      expect(
        HistorialTomas.recientes(registros, ahora: ahora, dias: 0),
        isEmpty,
      );
      expect(
        HistorialTomas.recientes(registros, ahora: ahora, limite: 0),
        isEmpty,
      );
    });
  });
}
