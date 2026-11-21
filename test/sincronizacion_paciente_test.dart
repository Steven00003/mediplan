import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/utils/sincronizacion_paciente.dart';

void main() {
  group('pacienteIdDesdeMensajeSincronizacion', () {
    test('acepta un mensaje sync con pacienteId válido', () {
      expect(
        pacienteIdDesdeMensajeSincronizacion({
          'tipo': 'sync',
          'pacienteId': ' pac-123 ',
        }),
        'pac-123',
      );
    });

    test('rechaza tipos incorrectos o id vacío', () {
      expect(
        pacienteIdDesdeMensajeSincronizacion({
          'tipo': 'otro',
          'pacienteId': 'x',
        }),
        isNull,
      );
      expect(
        pacienteIdDesdeMensajeSincronizacion({
          'tipo': 'sync',
          'pacienteId': '',
        }),
        isNull,
      );
      expect(pacienteIdDesdeMensajeSincronizacion({'tipo': 'sync'}), isNull);
      expect(pacienteIdDesdeMensajeSincronizacion({'pacienteId': 'x'}), isNull);
    });

    test('rechaza ids demasiado largos', () {
      final largo = 'a' * 129;
      expect(
        pacienteIdDesdeMensajeSincronizacion({
          'tipo': 'sync',
          'pacienteId': largo,
        }),
        isNull,
      );
    });
  });

  group('debeProcesarSincronizacion', () {
    test('procesa solo si todo coincide', () {
      expect(
        debeProcesarSincronizacion(
          pacienteIdMensaje: 'p1',
          pacienteIdLocal: 'p1',
          uidActual: 'uid1',
          dispositivoVinculadoId: 'uid1',
          sesionAnonima: true,
        ),
        isTrue,
      );
    });

    test('ignora paciente distinto, uid distinto o sesión no anónima', () {
      expect(
        debeProcesarSincronizacion(
          pacienteIdMensaje: 'p2',
          pacienteIdLocal: 'p1',
          uidActual: 'uid1',
          dispositivoVinculadoId: 'uid1',
          sesionAnonima: true,
        ),
        isFalse,
      );
      expect(
        debeProcesarSincronizacion(
          pacienteIdMensaje: 'p1',
          pacienteIdLocal: 'p1',
          uidActual: 'uid2',
          dispositivoVinculadoId: 'uid1',
          sesionAnonima: true,
        ),
        isFalse,
      );
      expect(
        debeProcesarSincronizacion(
          pacienteIdMensaje: 'p1',
          pacienteIdLocal: 'p1',
          uidActual: 'uid1',
          dispositivoVinculadoId: 'uid1',
          sesionAnonima: false,
        ),
        isFalse,
      );
    });

    test('ignora datos ausentes', () {
      expect(
        debeProcesarSincronizacion(
          pacienteIdMensaje: null,
          pacienteIdLocal: 'p1',
          uidActual: 'uid1',
          dispositivoVinculadoId: 'uid1',
          sesionAnonima: true,
        ),
        isFalse,
      );
    });
  });

  group('DebounceSincronizacion', () {
    test('envía después de 10 s desde el primer cambio', () {
      final debounce = DebounceSincronizacion();
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final gen = debounce.registrar('p1', t0);

      expect(
        debounce.retrasoPendiente(
          'p1',
          gen,
          t0.add(const Duration(seconds: 9)),
        ),
        const Duration(seconds: 1),
      );
      expect(
        debounce.debeEnviar('p1', gen, t0.add(const Duration(seconds: 9))),
        isFalse,
      );
      expect(
        debounce.debeEnviar('p1', gen, t0.add(const Duration(seconds: 10))),
        isTrue,
      );
    });

    test('reinicia el contador con un cambio nuevo', () {
      final debounce = DebounceSincronizacion();
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final gen1 = debounce.registrar('p1', t0);

      final t1 = t0.add(const Duration(seconds: 5));
      final gen2 = debounce.registrar('p1', t1);

      expect(
        debounce.retrasoPendiente(
          'p1',
          gen1,
          t1.add(const Duration(seconds: 5)),
        ),
        isNull,
      );
      expect(
        debounce.retrasoPendiente(
          'p1',
          gen2,
          t1.add(const Duration(seconds: 9)),
        ),
        const Duration(seconds: 1),
      );
      expect(
        debounce.debeEnviar('p1', gen2, t1.add(const Duration(seconds: 10))),
        isTrue,
      );
    });

    test('pacientes distintos no se mezclan', () {
      final debounce = DebounceSincronizacion();
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final gen1 = debounce.registrar('p1', t0);
      final gen2 = debounce.registrar('p2', t0.add(const Duration(seconds: 1)));

      expect(
        debounce.debeEnviar('p1', gen1, t0.add(const Duration(seconds: 10))),
        isTrue,
      );
      expect(
        debounce.debeEnviar('p2', gen2, t0.add(const Duration(seconds: 10))),
        isFalse,
      );
      expect(
        debounce.debeEnviar('p2', gen2, t0.add(const Duration(seconds: 11))),
        isTrue,
      );
    });

    test('limpiar deja el estado listo para una nueva generación', () {
      final debounce = DebounceSincronizacion();
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final gen = debounce.registrar('p1', t0);
      debounce.limpiar('p1', gen);

      final nuevo = debounce.registrar(
        'p1',
        t0.add(const Duration(minutes: 1)),
      );
      expect(nuevo, greaterThan(gen));
      expect(
        debounce.debeEnviar(
          'p1',
          nuevo,
          t0.add(const Duration(minutes: 1, seconds: 10)),
        ),
        isTrue,
      );
    });
  });
}
