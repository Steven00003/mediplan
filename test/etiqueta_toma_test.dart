// Pruebas del formateo de las filas del historial del detalle del paciente
// (`lib/utils/etiqueta_toma.dart`). No requiere Firebase ni widgets: es lógica de
// presentación pura, movida a `lib/utils/` justamente para poder testearla.
//
// El contrato que se fija aquí es el de "qué día es" y "qué hora se muestra":
// un error ahí no rompe la pantalla, se ve como una fecha mentirosa en el
// historial, que es justo lo que el cuidador usa para evaluar al paciente.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/registro_toma.dart';
import 'package:mediplan/utils/etiqueta_toma.dart';

void main() {
  // Referencia fija: las aserciones no dependen del reloj real.
  final ahora = DateTime(2026, 3, 11, 14, 30); // miércoles

  RegistroToma registro(DateTime programada, {DateTime? confirmada}) =>
      RegistroToma(
        id: 'r1',
        tratamientoId: 't1',
        pacienteId: 'p1',
        horaProgramada: programada,
        horaConfirmacion: confirmada,
        estado: EstadoToma.tomada,
      );

  group('horaCorta', () {
    test('rellena con cero a la izquierda', () {
      expect(horaCorta(DateTime(2026, 3, 11, 8, 5)), '08:05');
      expect(horaCorta(DateTime(2026, 3, 11, 20, 0)), '20:00');
      expect(horaCorta(DateTime(2026, 3, 11, 23, 59)), '23:59');
    });
  });

  group('etiquetaDia', () {
    test('hoy y ayer se nombran, sin número de día', () {
      expect(etiquetaDia(DateTime(2026, 3, 11, 8, 0), ahora: ahora), 'Hoy');
      expect(etiquetaDia(DateTime(2026, 3, 10, 23, 50), ahora: ahora), 'Ayer');
    });

    test('el mismo día de calendario cuenta como hoy aunque haya muchas horas',
        () {
      // 00:10 de hoy está a 14 h 20 de una toma de ayer, pero es HOY.
      expect(etiquetaDia(DateTime(2026, 3, 11, 0, 10), ahora: ahora), 'Hoy');
    });

    test('más atrás en el mismo año lleva día de la semana y número', () {
      expect(etiquetaDia(DateTime(2026, 3, 9, 20, 0), ahora: ahora), 'Lun 9');
      expect(etiquetaDia(DateTime(2026, 3, 1, 7, 0), ahora: ahora), 'Dom 1');
    });

    test('de otro año lleva mes y año', () {
      expect(
          etiquetaDia(DateTime(2025, 12, 24, 8, 0), ahora: ahora), '24 dic 2025');
    });

    test('cambiar de mes o de año no rompe el rótulo', () {
      expect(etiquetaDia(DateTime(2026, 2, 28, 8, 0), ahora: ahora), 'Sáb 28');
      expect(etiquetaDia(DateTime(2026, 1, 1, 8, 0), ahora: ahora), 'Jue 1');
    });
  });

  group('etiquetaProgramada', () {
    test('combina día y hora programada', () {
      expect(
        etiquetaProgramada(registro(DateTime(2026, 3, 11, 8, 0)), ahora: ahora),
        'Hoy · 08:00',
      );
      expect(
        etiquetaProgramada(registro(DateTime(2026, 3, 9, 20, 0)), ahora: ahora),
        'Lun 9 · 20:00',
      );
    });

    test('usa la hora PROGRAMADA, no la de confirmación', () {
      // Se confirmó a las 21:10 una toma de las 20:00: el rótulo del día y la
      // hora siguen siendo los de la toma, y la confirmación va aparte.
      final r = registro(
        DateTime(2026, 3, 11, 20, 0),
        confirmada: DateTime(2026, 3, 11, 21, 10),
      );
      expect(etiquetaProgramada(r, ahora: ahora), 'Hoy · 20:00');
      expect(horaConfirmacionCorta(r), '21:10');
    });
  });

  group('horaConfirmacionCorta', () {
    test('vuelve vacía si la toma nunca se confirmó', () {
      // Es el caso de `olvidada`: sellarle una hora mentiría sobre lo pasó.
      final r = RegistroToma(
        id: 'r2',
        tratamientoId: 't1',
        pacienteId: 'p1',
        horaProgramada: DateTime(2026, 3, 11, 8, 0),
        horaConfirmacion: null,
        estado: EstadoToma.olvidada,
      );
      expect(horaConfirmacionCorta(r), '');
    });

    test('refleja el `horaConfirmacion` tal cual, para cualquier estado', () {
      // El formateo no decide nada del estado: sólo formatea la hora si existe.
      // Que un estado *deba* o no *pueda* llevar hora de confirmación es regla
      // del modelo (`EstadoToma.registraConfirmacion`), no de esta función.
      for (final e in EstadoToma.values) {
        final conHora = registro(
          DateTime(2026, 3, 11, 8, 0),
          confirmada: DateTime(2026, 3, 11, 8, 2),
        );
        final conEstado = RegistroToma(
          id: 'r',
          tratamientoId: 't1',
          pacienteId: 'p1',
          horaProgramada: DateTime(2026, 3, 11, 8, 0),
          horaConfirmacion: DateTime(2026, 3, 11, 8, 2),
          estado: e,
        );
        expect(horaConfirmacionCorta(conEstado), '08:02',
            reason: 'con hora de confirmación, $e debe formatearla');
        expect(horaConfirmacionCorta(conHora), '08:02');
      }
    });
  });

  group('EstadoToma.registraConfirmacion', () {
    test('solo `olvidada` y `pendiente` llegan sin confirmar', () {
      // Guarda contra una regresión en la regla del modelo que el historial da
      // por hecha: una toma olvidada NUNCA se confirmó, y sellarle una hora
      // mentiría sobre lo que pasó.
      expect(EstadoToma.olvidada.registraConfirmacion, isFalse);
      expect(EstadoToma.pendiente.registraConfirmacion, isFalse);
      expect(EstadoToma.tomada.registraConfirmacion, isTrue);
      expect(EstadoToma.tardia.registraConfirmacion, isTrue);
      expect(EstadoToma.pospuesta.registraConfirmacion, isTrue);
    });
  });
}