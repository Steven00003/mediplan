// Pruebas de NotificacionesService.idDeAlarma. No requieren Firebase ni
// inicializar el plugin de notificaciones: solo se ejercita el cálculo del id,
// que es puro y estático.
//
// El id importa porque las alarmas se cancelan *recalculándolo* a partir de
// (tratamiento, hora, día) en vez de guardarlo. Si el hash dejara de ser
// determinista, las alarmas viejas sonarían sin poder cancelarlas; por eso la
// reproducibilidad se fija con valores literales y no solo con "dos llamadas
// iguales dan lo mismo".

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/services/notificaciones_service.dart';

void main() {
  // Rango que acepta `validateId` del plugin (int de 32 bits con signo). El 0
  // además está reservado por `idDeAlarma`.
  const minId = 1;
  const maxId = 0x7FFFFFFF;

  group('NotificacionesService.idDeAlarma', () {
    test('la misma terna siempre da el mismo id', () {
      final primera = NotificacionesService.idDeAlarma('t1', '08:00', 1);

      expect(NotificacionesService.idDeAlarma('t1', '08:00', 1), primera);
      expect(NotificacionesService.idDeAlarma('t1', '08:00', 1), primera);
    });

    test('el id está fijado: no cambia entre ejecuciones', () {
      // Si alguien cambia la fórmula del hash, estos valores dejan de cuadrar
      // y hay que actualizarlos a propósito (y revisar las alarmas ya
      // programadas en los dispositivos).
      expect(NotificacionesService.idDeAlarma('t1', '08:00', 1), 829727912);
      expect(NotificacionesService.idDeAlarma('t1', '08:00', 2), 829727913);
      expect(NotificacionesService.idDeAlarma('t1', '20:00', 1), 228218418);
      expect(NotificacionesService.idDeAlarma('t2', '08:00', 1), 1169757097);
      expect(NotificacionesService.idDeAlarma('abc', '07:30', 7), 1654431313);
    });

    test('horas distintas del mismo tratamiento y día no colisionan', () {
      expect(NotificacionesService.idDeAlarma('t1', '08:00', 1),
          isNot(NotificacionesService.idDeAlarma('t1', '20:00', 1)));
      expect(NotificacionesService.idDeAlarma('t1', '08:00', 1),
          isNot(NotificacionesService.idDeAlarma('t1', '08:30', 1)));
    });

    test('días distintos de la misma hora y tratamiento no colisionan', () {
      final porDia = <int, int>{};
      for (var dia = 1; dia <= 7; dia++) {
        porDia[dia] = NotificacionesService.idDeAlarma('t1', '08:00', dia);
      }

      expect(porDia.values.toSet().length, 7);
    });

    test('tratamientos distintos con la misma hora y día no colisionan', () {
      expect(NotificacionesService.idDeAlarma('t1', '08:00', 1),
          isNot(NotificacionesService.idDeAlarma('t2', '08:00', 1)));
    });

    test('un conjunto representativo de tomas reales no repite ids', () {
      // 3 tratamientos x 3 horarios x 7 días, como un paciente con varios
      // medicamentos a distintas horas.
      const tratamientos = ['t1', 't2', 't3'];
      const horas = ['07:00', '13:30', '21:00'];
      const dias = [1, 2, 3, 4, 5, 6, 7];

      final ids = <int>[];
      for (final t in tratamientos) {
        for (final hora in horas) {
          for (final dia in dias) {
            ids.add(NotificacionesService.idDeAlarma(t, hora, dia));
          }
        }
      }

      expect(ids.length, 63);
      expect(ids.toSet().length, 63);
    });

    test('el id siempre es válido para el plugin y nunca es 0', () {
      for (final t in ['t1', 't2', 't3', 'id-muy-largo-con-guiones']) {
        for (final hora in ['00:00', '08:00', '23:59']) {
          for (var dia = 1; dia <= 7; dia++) {
            final id = NotificacionesService.idDeAlarma(t, hora, dia);
            expect(id, greaterThanOrEqualTo(minId));
            expect(id, lessThanOrEqualTo(maxId));
            expect(id, isNot(0));
          }
        }
      }
    });
  });
}
