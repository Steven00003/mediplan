// Pruebas puras de los ids y del cálculo de horarios de las notificaciones
// locales del paciente (aviso previo, felicitación y recordatorio tardío).
// No inicializan el plugin de notificaciones ni Firebase.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/services/notificaciones_service.dart';

void main() {
  group('ids de notificaciones del paciente', () {
    test('el aviso previo cae en su rango negativo', () {
      final id = NotificacionesService.idDeAvisoPrevio('t1', '08:00', 1);

      expect(id, isNegative);
      expect(
        id,
        inInclusiveRange(
          NotificacionesService.minIdAvisoPrevio,
          NotificacionesService.maxIdAvisoPrevio,
        ),
      );
    });

    test('la felicitación cae en su rango negativo', () {
      final id = NotificacionesService.idDeFelicitacion(
        't1',
        DateTime(2026, 1, 5, 8, 0),
      );

      expect(id, isNegative);
      expect(
        id,
        inInclusiveRange(
          NotificacionesService.minIdFelicitacion,
          NotificacionesService.maxIdFelicitacion,
        ),
      );
    });

    test('el recordatorio tardío cae en su rango negativo', () {
      final id = NotificacionesService.idDeRecordatorioTardio('t1', '08:00', 1);

      expect(id, isNegative);
      expect(
        id,
        inInclusiveRange(
          NotificacionesService.minIdRecordatorioTardio,
          NotificacionesService.maxIdRecordatorioTardio,
        ),
      );
    });

    test('el tardío puntual de posponer cae en su subrango', () {
      final id = NotificacionesService.idDeRecordatorioTardioPospuesto(
        't1',
        DateTime(2026, 1, 5, 8, 5),
      );

      expect(id, isNegative);
      expect(
        id,
        inInclusiveRange(
          NotificacionesService.minIdRecordatorioTardioPospuesto,
          NotificacionesService.maxIdRecordatorioTardioPospuesto,
        ),
      );
    });

    test('los ids son estables para la misma entrada', () {
      expect(
        NotificacionesService.idDeAvisoPrevio('t1', '08:00', 1),
        NotificacionesService.idDeAvisoPrevio('t1', '08:00', 1),
      );
      expect(
        NotificacionesService.idDeFelicitacion('t1', DateTime(2026, 1, 5, 8)),
        NotificacionesService.idDeFelicitacion('t1', DateTime(2026, 1, 5, 8)),
      );
      expect(
        NotificacionesService.idDeRecordatorioTardio('t1', '08:00', 1),
        NotificacionesService.idDeRecordatorioTardio('t1', '08:00', 1),
      );
      expect(
        NotificacionesService.idDeRecordatorioTardioPospuesto(
          't1',
          DateTime(2026, 1, 5, 8, 5),
        ),
        NotificacionesService.idDeRecordatorioTardioPospuesto(
          't1',
          DateTime(2026, 1, 5, 8, 5),
        ),
      );
    });

    test('no chocan con el id de la alarma ni entre tipos', () {
      const tratamientos = ['t1', 't2', 't3'];
      const horas = ['08:00', '12:30', '20:15', '23:55'];
      const dias = [1, 2, 3, 4, 5, 6, 7];

      final alarma = <int>{};
      final avisos = <int>{};
      final tardios = <int>{};
      final felicitaciones = <int>{};
      final pospuestos = <int>{};

      for (final t in tratamientos) {
        for (final h in horas) {
          for (final d in dias) {
            alarma.add(NotificacionesService.idDeAlarma(t, h, d));
            avisos.add(NotificacionesService.idDeAvisoPrevio(t, h, d));
            tardios.add(NotificacionesService.idDeRecordatorioTardio(t, h, d));
          }
        }
        for (var mes = 1; mes <= 12; mes++) {
          felicitaciones.add(
            NotificacionesService.idDeFelicitacion(
              t,
              DateTime(2026, mes, 5, 8, 0),
            ),
          );
          pospuestos.add(
            NotificacionesService.idDeRecordatorioTardioPospuesto(
              t,
              DateTime(2026, mes, 5, 8, 5),
            ),
          );
        }
      }

      // La alarma usa ids positivos; los tres tipos nuevos, negativos.
      expect(alarma.every((id) => id > 0), isTrue);
      expect(avisos.every((id) => id < 0), isTrue);
      expect(tardios.every((id) => id < 0), isTrue);
      expect(felicitaciones.every((id) => id < 0), isTrue);
      expect(pospuestos.every((id) => id < 0), isTrue);

      // Los rangos de los tipos nuevos son disjuntos entre sí.
      expect(avisos.intersection(tardios), isEmpty);
      expect(avisos.intersection(felicitaciones), isEmpty);
      expect(avisos.intersection(pospuestos), isEmpty);
      expect(tardios.intersection(felicitaciones), isEmpty);
      expect(tardios.intersection(pospuestos), isEmpty);
      expect(felicitaciones.intersection(pospuestos), isEmpty);

      // Y ninguno puede coincidir con una alarma positiva.
      for (final conjunto in [avisos, tardios, felicitaciones, pospuestos]) {
        expect(conjunto.intersection(alarma), isEmpty);
      }
    });
  });

  group('desplazarHoraYDia', () {
    test('resta 5 minutos sin cambiar de día', () {
      expect(NotificacionesService.desplazarHoraYDia('08:00', 1, -5), (
        '07:55',
        1,
      ));
    });

    test('el aviso de una toma a las 00:03 cae el día anterior', () {
      expect(NotificacionesService.desplazarHoraYDia('00:03', 1, -5), (
        '23:58',
        7,
      ));
    });

    test('el tardío de una toma a las 23:55 cae al día siguiente', () {
      expect(NotificacionesService.desplazarHoraYDia('23:55', 7, 15), (
        '00:10',
        1,
      ));
    });

    test('suma 15 minutos sin cruzar medianoche', () {
      expect(NotificacionesService.desplazarHoraYDia('08:00', 3, 15), (
        '08:15',
        3,
      ));
    });

    test('cruza medianoche justo a las 00:00', () {
      expect(NotificacionesService.desplazarHoraYDia('23:50', 6, 15), (
        '00:05',
        7,
      ));
    });
  });
}
