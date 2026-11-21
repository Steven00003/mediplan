import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/utils/telefono_emergencia.dart';

void main() {
  group('normalizarTelefonoEmergencia', () {
    test('acepta espacios y guiones', () {
      expect(normalizarTelefonoEmergencia('+57 300-123-4567'), '+573001234567');
      expect(normalizarTelefonoEmergencia('300 123 4567'), '3001234567');
    });

    test('conserva el +57 inicial', () {
      expect(normalizarTelefonoEmergencia('+57 300 123 4567'), '+573001234567');
    });

    test('vacío no es válido', () {
      expect(normalizarTelefonoEmergencia(''), isNull);
      expect(normalizarTelefonoEmergencia('   '), isNull);
      expect(normalizarTelefonoEmergencia(null), isNull);
    });

    test('muy corto no es válido', () {
      expect(normalizarTelefonoEmergencia('123456'), isNull);
    });

    test('muy largo no es válido', () {
      expect(normalizarTelefonoEmergencia('1234567890123456'), isNull);
    });

    test('con letras: las quita y valida los dígitos restantes', () {
      expect(normalizarTelefonoEmergencia('abc'), isNull);
      expect(
        normalizarTelefonoEmergencia('+57 abc 300 123 4567'),
        '+573001234567',
      );
    });

    test('acepta los límites de 7 y 15 dígitos', () {
      expect(normalizarTelefonoEmergencia('1234567'), '1234567');
      expect(
        normalizarTelefonoEmergencia('123456789012345'),
        '123456789012345',
      );
    });
  });
}
