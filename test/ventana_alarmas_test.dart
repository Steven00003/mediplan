// Pruebas puras de la ventana móvil de alarmas puntuales.
//
// No inicializan el plugin ni Firebase: solo ejercitan la generación de
// ocurrencias, los ids reproducibles y los ids que se cancelan.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/services/notificaciones_service.dart';
import 'package:mediplan/utils/ventana_alarmas.dart';

HorarioDia horario(String hora, List<int> dias) =>
    HorarioDia(hora: hora, dias: dias);

void main() {
  group('VentanaAlarmas.ocurrencias', () {
    test('genera 7 días y cruza medianoche/cambio de semana', () {
      // Domingo 4 de enero de 2026, 23:00.
      final ahora = DateTime(2026, 1, 4, 23, 0);
      final ocurrencias = VentanaAlarmas.ocurrencias(
        tratamientoId: 't1',
        horarios: [
          horario('23:55', [DateTime.sunday]),
          horario('00:05', [DateTime.monday]),
        ],
        ahora: ahora,
      );

      expect(ocurrencias, hasLength(2));
      expect(ocurrencias[0].horaProgramada, DateTime(2026, 1, 4, 23, 55));
      expect(ocurrencias[0].hora, '23:55');
      // El lunes 5 a las 00:05 ya es el día siguiente y la semana siguiente.
      expect(ocurrencias[1].horaProgramada, DateTime(2026, 1, 5, 0, 5));
      expect(ocurrencias[1].hora, '00:05');
    });

    test('respeta fechaInicio y duración inclusiva', () {
      final ahora = DateTime(2026, 1, 5, 7, 0); // lunes
      final ocurrencias = VentanaAlarmas.ocurrencias(
        tratamientoId: 't1',
        horarios: [horario('08:00', HorarioDia.todosLosDias)],
        ahora: ahora,
        fechaInicio: DateTime(2026, 1, 6),
        duracionDias: 2,
      );

      expect(ocurrencias.map((o) => o.horaProgramada).toList(), [
        DateTime(2026, 1, 6, 8, 0),
        DateTime(2026, 1, 7, 8, 0),
      ]);
    });

    test('no genera nada si el tratamiento ya terminó', () {
      final ahora = DateTime(2026, 1, 5, 7, 0);
      final ocurrencias = VentanaAlarmas.ocurrencias(
        tratamientoId: 't1',
        horarios: [horario('08:00', HorarioDia.todosLosDias)],
        ahora: ahora,
        fechaInicio: DateTime(2026, 1, 1),
        duracionDias: 2,
      );

      expect(ocurrencias, isEmpty);
    });

    test(
      'con fechaInicio sin duración programa hasta el final de la ventana',
      () {
        final ahora = DateTime(2026, 1, 5, 7, 0);
        final ocurrencias = VentanaAlarmas.ocurrencias(
          tratamientoId: 't1',
          horarios: [horario('08:00', HorarioDia.todosLosDias)],
          ahora: ahora,
          fechaInicio: DateTime(2026, 1, 6),
        );

        // Del 6 al 11 de enero (la ventana es del 5 al 11).
        expect(ocurrencias, hasLength(6));
        expect(ocurrencias.first.horaProgramada, DateTime(2026, 1, 6, 8, 0));
        expect(ocurrencias.last.horaProgramada, DateTime(2026, 1, 11, 8, 0));
      },
    );

    test('varios horarios se ordenan y no se duplican', () {
      final ahora = DateTime(2026, 1, 5, 6, 0);
      final ocurrencias = VentanaAlarmas.ocurrencias(
        tratamientoId: 't1',
        horarios: [
          horario('20:00', [1, 3, 5]),
          horario('08:00', HorarioDia.todosLosDias),
          // Duplicado exacto: debe producir la misma ocurrencia/id.
          horario('08:00', HorarioDia.todosLosDias),
        ],
        ahora: ahora,
      );

      // 7 tomas de las 08:00 + 3 de las 20:00 (lunes, miércoles y viernes).
      expect(ocurrencias, hasLength(10));
      expect(ocurrencias.map((o) => o.id).toSet(), hasLength(10));
      for (var i = 1; i < ocurrencias.length; i++) {
        expect(
          ocurrencias[i - 1].horaProgramada.isAfter(
            ocurrencias[i].horaProgramada,
          ),
          isFalse,
        );
      }
    });

    test('las ocurrencias de hoy ya pasadas no se programan', () {
      final ahora = DateTime(2026, 1, 5, 9, 0);
      final ocurrencias = VentanaAlarmas.ocurrencias(
        tratamientoId: 't1',
        horarios: [horario('08:00', HorarioDia.todosLosDias)],
        ahora: ahora,
      );

      expect(
        ocurrencias.any((o) => o.horaProgramada == DateTime(2026, 1, 5, 8, 0)),
        isFalse,
      );
      expect(ocurrencias.first.horaProgramada, DateTime(2026, 1, 6, 8, 0));
    });
  });

  group('VentanaAlarmas.idDeOcurrencia', () {
    test('es estable y cae en el subrango reservado', () {
      final fecha = DateTime(2026, 1, 5, 8, 0);
      final id = VentanaAlarmas.idDeOcurrencia('t1', fecha);

      expect(VentanaAlarmas.idDeOcurrencia('t1', fecha), id);
      // Valor literal para detectar un cambio accidental de hash/fórmula.
      expect(id, -967077465);
      expect(
        id,
        inInclusiveRange(
          VentanaAlarmas.minIdAlarmaPuntual,
          VentanaAlarmas.maxIdAlarmaPuntual,
        ),
      );
      expect(NotificacionesService.idDeAlarmaPuntual('t1', fecha), id);
    });

    test('distingue tratamiento, fecha y hora', () {
      final base = DateTime(2026, 1, 5, 8, 0);
      final ids = {
        VentanaAlarmas.idDeOcurrencia('t1', base),
        VentanaAlarmas.idDeOcurrencia('t2', base),
        VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 6, 8, 0)),
        VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 5, 9, 0)),
      };

      expect(ids, hasLength(4));
    });

    test('63 ocurrencias no colisionan y no invaden otros rangos', () {
      final ahora = DateTime(2026, 1, 5, 6, 0);
      final ids = <int>[];
      for (var t = 0; t < 3; t++) {
        final ocurrencias = VentanaAlarmas.ocurrencias(
          tratamientoId: 't$t',
          horarios: [
            horario('08:00', HorarioDia.todosLosDias),
            horario('14:00', HorarioDia.todosLosDias),
            horario('20:00', HorarioDia.todosLosDias),
          ],
          ahora: ahora,
        );
        expect(ocurrencias, hasLength(21));
        ids.addAll(ocurrencias.map((o) => o.id));
      }

      expect(ids, hasLength(63));
      expect(ids.toSet(), hasLength(63));
      for (final id in ids) {
        expect(
          id,
          inInclusiveRange(
            VentanaAlarmas.minIdAlarmaPuntual,
            VentanaAlarmas.maxIdAlarmaPuntual,
          ),
        );
        expect(
          id,
          isNot(
            inInclusiveRange(
              NotificacionesService.minIdRecordatorioTardioPospuesto,
              NotificacionesService.maxIdRecordatorioTardioPospuesto,
            ),
          ),
        );
      }
    });
  });

  group('VentanaAlarmas.idsDeOcurrencias (cancelación)', () {
    test('incluye todas las ocurrencias futuras de la ventana', () {
      final ahora = DateTime(2026, 1, 5, 6, 0);
      final ids = VentanaAlarmas.idsDeOcurrencias(
        tratamientoId: 't1',
        horarios: [
          horario('08:00', HorarioDia.todosLosDias),
          horario('20:00', [1, 3, 5]),
        ],
        ahora: ahora,
        respetarVigencia: false,
      );

      expect(ids, hasLength(10));
      expect(ids.toSet(), hasLength(10));
      expect(
        ids,
        contains(
          VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 5, 8, 0)),
        ),
      );
      expect(
        ids,
        contains(
          VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 11, 8, 0)),
        ),
      );
      expect(
        ids,
        isNot(
          contains(
            VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 12, 8, 0)),
          ),
        ),
      );
    });

    test('la cancelación no toca una ocurrencia de hoy ya pasada', () {
      final ahora = DateTime(2026, 1, 5, 9, 0);
      final ids = VentanaAlarmas.idsDeOcurrencias(
        tratamientoId: 't1',
        horarios: [horario('08:00', HorarioDia.todosLosDias)],
        ahora: ahora,
        respetarVigencia: false,
      );

      expect(
        ids,
        isNot(
          contains(
            VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 5, 8, 0)),
          ),
        ),
      );
      expect(
        ids,
        contains(
          VentanaAlarmas.idDeOcurrencia('t1', DateTime(2026, 1, 6, 8, 0)),
        ),
      );
    });
  });

  test('un caso razonable queda muy por debajo del límite de 500', () {
    // 3 tratamientos x 3 horarios diarios x 7 días = 63 alarmas puntuales.
    final ahora = DateTime(2026, 1, 5, 6, 0);
    var puntuales = 0;
    for (var t = 0; t < 3; t++) {
      puntuales += VentanaAlarmas.ocurrencias(
        tratamientoId: 't$t',
        horarios: [
          horario('08:00', HorarioDia.todosLosDias),
          horario('14:00', HorarioDia.todosLosDias),
          horario('20:00', HorarioDia.todosLosDias),
        ],
        ahora: ahora,
      ).length;
    }

    // Cada horario conserva un aviso previo y un tardío semanales por día.
    final otras = 3 * 3 * 7 * 2;
    expect(puntuales, 63);
    expect(puntuales + otras, lessThan(500));
  });
}
