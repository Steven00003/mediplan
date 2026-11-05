// Pruebas puras de la próxima toma y de la cuenta regresiva.
//
// 2026-11-02 es lunes. Los casos cubren el mismo día, el día siguiente, la
// vuelta de semana, varios horarios, el cruce de medianoche y el final del
// tratamiento antes de la siguiente dosis.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/utils/proxima_toma.dart';

Tratamiento _tratamiento({
  required List<HorarioDia> horarios,
  DateTime? fechaInicio,
  int? duracionDias,
}) {
  return Tratamiento(
    id: 't1',
    pacienteId: 'p1',
    nombreMedicamento: 'Paracetamol',
    dosis: '1',
    horarios: horarios,
    frecuencia: 'Diaria',
    fechaInicio: fechaInicio,
    duracionDias: duracionDias,
  );
}

void main() {
  final lunes = DateTime(2026, 11, 2);
  final todosLosDias = HorarioDia.todosLosDias;

  group('ProximaToma.calcular', () {
    test('encuentra otra toma del mismo día', () {
      final t = _tratamiento(
        horarios: [
          HorarioDia(hora: '08:00', dias: todosLosDias),
          HorarioDia(hora: '20:00', dias: todosLosDias),
        ],
      );
      final ahora = DateTime(2026, 11, 2, 8);
      final actual = DateTime(2026, 11, 2, 8);

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: ahora,
        tomaActual: actual,
      );

      expect(resultado.esUltima, isFalse);
      expect(resultado.cuando, DateTime(2026, 11, 2, 20));
    });

    test('pasa al día siguiente cuando ya no hay más tomas hoy', () {
      final t = _tratamiento(
        horarios: [HorarioDia(hora: '08:00', dias: todosLosDias)],
      );
      final ahora = DateTime(2026, 11, 2, 8);
      final actual = DateTime(2026, 11, 2, 8);

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: ahora,
        tomaActual: actual,
      );

      expect(resultado.cuando, DateTime(2026, 11, 3, 8));
      expect(resultado.esUltima, isFalse);
    });

    test('da la vuelta a la semana', () {
      final soloLunes = _tratamiento(
        horarios: [
          HorarioDia(hora: '08:00', dias: const [1]),
        ],
      );
      final ahora = DateTime(2026, 11, 2, 8);
      final actual = DateTime(2026, 11, 2, 8);

      final resultado = ProximaToma.calcular(
        tratamiento: soloLunes,
        ahora: ahora,
        tomaActual: actual,
      );

      expect(resultado.cuando, DateTime(2026, 11, 9, 8));
    });

    test('elige el siguiente horario entre varios del mismo día', () {
      final t = _tratamiento(
        horarios: [
          HorarioDia(hora: '08:00', dias: todosLosDias),
          HorarioDia(hora: '14:00', dias: todosLosDias),
          HorarioDia(hora: '20:00', dias: todosLosDias),
        ],
      );
      final ahora = DateTime(2026, 11, 2, 8);
      final actual = DateTime(2026, 11, 2, 8);

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: ahora,
        tomaActual: actual,
      );

      expect(resultado.cuando, DateTime(2026, 11, 2, 14));
    });

    test('cruza la medianoche', () {
      final t = _tratamiento(
        horarios: [
          HorarioDia(hora: '23:50', dias: todosLosDias),
          HorarioDia(hora: '00:10', dias: todosLosDias),
        ],
      );
      final ahora = DateTime(2026, 11, 2, 23, 50);
      final actual = DateTime(2026, 11, 2, 23, 50);

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: ahora,
        tomaActual: actual,
      );

      expect(resultado.cuando, DateTime(2026, 11, 3, 0, 10));
    });

    test('excluye la toma actual aunque la alarma abra antes de la hora', () {
      final t = _tratamiento(
        horarios: [HorarioDia(hora: '08:00', dias: todosLosDias)],
      );
      final ahora = DateTime(2026, 11, 2, 7, 59);
      final actual = DateTime(2026, 11, 2, 8);

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: ahora,
        tomaActual: actual,
      );

      expect(resultado.cuando, DateTime(2026, 11, 3, 8));
    });

    test('marca la última toma cuando la siguiente cae después del fin', () {
      final t = _tratamiento(
        horarios: [HorarioDia(hora: '08:00', dias: todosLosDias)],
        fechaInicio: lunes,
        duracionDias: 1,
      );

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: DateTime(2026, 11, 2, 8),
        tomaActual: DateTime(2026, 11, 2, 8),
      );

      expect(resultado.esUltima, isTrue);
      expect(resultado.cuando, isNull);
    });

    test('no marca la última si la siguiente todavía cae dentro del fin', () {
      final t = _tratamiento(
        horarios: [HorarioDia(hora: '08:00', dias: todosLosDias)],
        fechaInicio: lunes,
        duracionDias: 2,
      );

      final resultado = ProximaToma.calcular(
        tratamiento: t,
        ahora: DateTime(2026, 11, 2, 8),
        tomaActual: DateTime(2026, 11, 2, 8),
      );

      expect(resultado.esUltima, isFalse);
      expect(resultado.cuando, DateTime(2026, 11, 3, 8));
    });
  });

  group('ProximaToma.formatearCuentaRegresiva', () {
    test('horas y minutos', () {
      expect(
        ProximaToma.formatearCuentaRegresiva(
          const Duration(hours: 3, minutes: 25),
        ),
        'Faltan 3 h 25 min',
      );
    });

    test('minutos y segundos cuando falta menos de una hora', () {
      expect(
        ProximaToma.formatearCuentaRegresiva(
          const Duration(minutes: 59, seconds: 5),
        ),
        'Faltan 59 min 05 s',
      );
    });

    test('solo segundos cuando falta menos de un minuto', () {
      expect(
        ProximaToma.formatearCuentaRegresiva(const Duration(seconds: 42)),
        'Faltan 42 s',
      );
    });

    test('días cuando falta más de 24 horas', () {
      expect(
        ProximaToma.formatearCuentaRegresiva(
          const Duration(days: 1, hours: 3, minutes: 25),
        ),
        'Faltan 1 d 3 h 25 min',
      );
    });

    test('nunca muestra una cuenta negativa', () {
      expect(
        ProximaToma.formatearCuentaRegresiva(const Duration(seconds: -8)),
        'Faltan 0 s',
      );
    });
  });
}
