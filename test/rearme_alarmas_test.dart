// Pruebas puras del rearme incremental de la ventana de alarmas.
//
// No tocan el plugin, SharedPreferences ni Firestore: solo comparan el
// conjunto deseado con el realmente programado y el guard de solapamiento.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/utils/guard_rearme.dart';
import 'package:mediplan/utils/rearme_alarmas.dart';
import 'package:mediplan/utils/ventana_alarmas.dart';

OcurrenciaAlarma ocurrencia(String tratamientoId, DateTime hora) {
  final hh = hora.hour.toString().padLeft(2, '0');
  final mm = hora.minute.toString().padLeft(2, '0');
  return OcurrenciaAlarma(
    tratamientoId: tratamientoId,
    horaProgramada: hora,
    hora: '$hh:$mm',
  );
}

void main() {
  final ahora = DateTime(2026, 1, 5, 6, 0);

  group('CalculadoraRearme.calcular', () {
    test('no hay nada que hacer cuando id y hora coinciden', () {
      final deseada = ocurrencia('t1', DateTime(2026, 1, 5, 8, 0));
      final plan = CalculadoraRearme.calcular(
        deseadas: [deseada],
        actuales: [AlarmaActual(id: deseada.id, hora: deseada.horaProgramada)],
        ahora: ahora,
      );

      expect(plan.vacio, isTrue);
      expect(plan.conservar, hasLength(1));
      expect(plan.cancelar, isEmpty);
      expect(plan.programar, isEmpty);
    });

    test('programa solo la ocurrencia que falta', () {
      final primera = ocurrencia('t1', DateTime(2026, 1, 5, 8, 0));
      final segunda = ocurrencia('t1', DateTime(2026, 1, 5, 9, 0));
      final plan = CalculadoraRearme.calcular(
        deseadas: [primera, segunda],
        actuales: [AlarmaActual(id: primera.id, hora: primera.horaProgramada)],
        ahora: ahora,
      );

      expect(plan.cancelar, isEmpty);
      expect(plan.programar.map((o) => o.id), [segunda.id]);
      expect(plan.conservar.map((o) => o.id), [primera.id]);
    });

    test('cancela solo la ocurrencia que sobra', () {
      final deseada = ocurrencia('t1', DateTime(2026, 1, 5, 8, 0));
      final sobrante = ocurrencia('t1', DateTime(2026, 1, 5, 9, 0));
      final plan = CalculadoraRearme.calcular(
        deseadas: [deseada],
        actuales: [
          AlarmaActual(id: deseada.id, hora: deseada.horaProgramada),
          AlarmaActual(id: sobrante.id, hora: sobrante.horaProgramada),
        ],
        ahora: ahora,
      );

      expect(plan.cancelar, [sobrante.id]);
      expect(plan.programar, isEmpty);
      expect(plan.conservar.map((o) => o.id), [deseada.id]);
    });

    test('si cambió la hora cancela la vieja y programa la nueva', () {
      final vieja = ocurrencia('t1', DateTime(2026, 1, 5, 8, 0));
      final nueva = ocurrencia('t1', DateTime(2026, 1, 5, 9, 0));
      final plan = CalculadoraRearme.calcular(
        deseadas: [nueva],
        actuales: [AlarmaActual(id: vieja.id, hora: vieja.horaProgramada)],
        ahora: ahora,
      );

      expect(plan.cancelar, [vieja.id]);
      expect(plan.programar.map((o) => o.id), [nueva.id]);
      expect(plan.conservar, isEmpty);
    });

    test('no cancela una alarma sobrante que es inminente', () {
      final inminente = ocurrencia(
        't1',
        ahora.add(const Duration(seconds: 60)),
      );
      final plan = CalculadoraRearme.calcular(
        deseadas: const [],
        actuales: [
          AlarmaActual(id: inminente.id, hora: inminente.horaProgramada),
        ],
        ahora: ahora,
      );

      expect(plan.vacio, isTrue);
      expect(plan.cancelar, isEmpty);
    });

    test('no reprograma una coincidente que es inminente', () {
      final inminente = ocurrencia(
        't1',
        ahora.add(const Duration(seconds: 60)),
      );
      final plan = CalculadoraRearme.calcular(
        deseadas: [inminente],
        actuales: [
          AlarmaActual(id: inminente.id, hora: inminente.horaProgramada),
        ],
        ahora: ahora,
      );

      expect(plan.vacio, isTrue);
      expect(plan.conservar, hasLength(1));
    });

    test('no cancela una que disparó hace menos de 2 minutos', () {
      final reciente = ocurrencia(
        't1',
        ahora.subtract(const Duration(seconds: 60)),
      );
      final plan = CalculadoraRearme.calcular(
        deseadas: const [],
        actuales: [AlarmaActual(id: reciente.id, hora: reciente.horaProgramada)],
        ahora: ahora,
      );

      expect(plan.vacio, isTrue);
      expect(plan.cancelar, isEmpty);
    });

    test('programa una faltante aunque sea inminente', () {
      final inminente = ocurrencia(
        't1',
        ahora.add(const Duration(seconds: 60)),
      );
      final plan = CalculadoraRearme.calcular(
        deseadas: [inminente],
        actuales: const [],
        ahora: ahora,
      );

      expect(plan.programar.map((o) => o.id), [inminente.id]);
      expect(plan.cancelar, isEmpty);
    });
  });

  group('CalculadoraRearme.protegida', () {
    test('protege hasta 90 s antes y 2 min después', () {
      expect(
        CalculadoraRearme.protegida(
          ahora.add(const Duration(seconds: 89)),
          ahora,
        ),
        isTrue,
      );
      expect(
        CalculadoraRearme.protegida(
          ahora.add(const Duration(seconds: 90)),
          ahora,
        ),
        isFalse,
      );
      expect(
        CalculadoraRearme.protegida(
          ahora.subtract(const Duration(seconds: 119)),
          ahora,
        ),
        isTrue,
      );
      expect(
        CalculadoraRearme.protegida(
          ahora.subtract(const Duration(minutes: 2)),
          ahora,
        ),
        isFalse,
      );
      expect(CalculadoraRearme.protegida(null, ahora), isFalse);
    });
  });

  group('GuardRearme', () {
    test('rechaza un segundo rearme mientras el primero está activo', () {
      final guard = GuardRearme();
      expect(guard.activo, isFalse);

      expect(guard.entrar(), isTrue);
      expect(guard.activo, isTrue);
      expect(guard.entrar(), isFalse);

      guard.salir();
      expect(guard.activo, isFalse);
      expect(guard.entrar(), isTrue);
    });

    test('salir es idempotente', () {
      final guard = GuardRearme();
      guard.entrar();
      guard.salir();
      guard.salir();
      expect(guard.activo, isFalse);
    });
  });
}
