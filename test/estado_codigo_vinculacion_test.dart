import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/utils/estado_codigo_vinculacion.dart';

void main() {
  final ahora = DateTime(2026, 11, 12, 10, 30);

  test('un código con fecha futura está vigente', () {
    expect(
      estadoDelCodigo(ahora.add(const Duration(minutes: 1)), ahora),
      EstadoCodigoVinculacion.vigente,
    );
  });

  test('un código con fecha pasada está vencido', () {
    expect(
      estadoDelCodigo(ahora.subtract(const Duration(minutes: 1)), ahora),
      EstadoCodigoVinculacion.vencido,
    );
  });

  test('justo en el límite ya está vencido', () {
    expect(estadoDelCodigo(ahora, ahora), EstadoCodigoVinculacion.vencido);
  });

  test('un vínculo sin expiraEn se trata como vigente', () {
    expect(
      estadoDelCodigo(null, ahora),
      EstadoCodigoVinculacion.sinVencimiento,
    );
  });

  test('el texto usa dd/mm y HH:mm, incluso al cambiar de día', () {
    final expira = DateTime(2026, 11, 13, 0, 5);
    expect(
      textoVencimientoCodigo(expira, DateTime(2026, 11, 12, 23, 55)),
      'Vence el 13/11 a las 00:05',
    );
  });

  test('el texto de un código vencido es explícito', () {
    expect(textoVencimientoCodigo(ahora, ahora), 'Código vencido');
  });

  test('el texto sin fecha no inventa un vencimiento', () {
    expect(textoVencimientoCodigo(null, ahora), 'Sin vencimiento');
  });
}
