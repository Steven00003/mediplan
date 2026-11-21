import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/utils/validacion_ficha_paciente.dart';

void main() {
  group('nombre', () {
    test('es obligatorio y se recorta sin espacios sobrantes', () {
      final resultado = validarFichaPaciente(
        nombre: '  María   Fernanda  ',
        edad: '',
        condicion: '',
        contactoEmergencia: '',
      );

      expect(resultado.esValida, isTrue);
      expect(resultado.datos!.nombre, 'María Fernanda');
    });

    test('solo espacios no es un nombre válido', () {
      final resultado = validarFichaPaciente(
        nombre: '   ',
        edad: '',
        condicion: '',
        contactoEmergencia: '',
      );

      expect(resultado.esValida, isFalse);
      expect(resultado.error, 'Ingresa el nombre del paciente.');
    });
  });

  group('edad', () {
    test('es opcional y acepta 0 y 120 como límites', () {
      for (final edad in ['0', '120']) {
        final resultado = validarFichaPaciente(
          nombre: 'Ana',
          edad: edad,
          condicion: '',
          contactoEmergencia: '',
        );
        expect(resultado.esValida, isTrue, reason: 'edad $edad');
        expect(resultado.datos!.edad, int.parse(edad));
      }

      final sinEdad = validarFichaPaciente(
        nombre: 'Ana',
        edad: '   ',
        condicion: '',
        contactoEmergencia: '',
      );
      expect(sinEdad.esValida, isTrue);
      expect(sinEdad.datos!.edad, isNull);
    });

    test('rechaza fuera de rango y valores no numéricos', () {
      for (final edad in ['-1', '121', 'abc']) {
        final resultado = validarFichaPaciente(
          nombre: 'Ana',
          edad: edad,
          condicion: '',
          contactoEmergencia: '',
        );
        expect(resultado.esValida, isFalse, reason: 'edad $edad');
        expect(resultado.error, 'La edad debe estar entre 0 y 120 años.');
      }
    });
  });

  group('teléfono', () {
    test('acepta + y espacios al escribir y guarda normalizado', () {
      final resultado = validarFichaPaciente(
        nombre: 'Ana',
        edad: '',
        condicion: '',
        contactoEmergencia: '+34 600 000 000',
      );

      expect(resultado.esValida, isTrue);
      expect(resultado.datos!.contactoEmergencia, '+34600000000');
    });

    test('acepta entre 7 y 15 dígitos y vacío como null', () {
      for (final telefono in ['1234567', '123456789012345']) {
        final resultado = validarFichaPaciente(
          nombre: 'Ana',
          edad: '',
          condicion: '',
          contactoEmergencia: telefono,
        );
        expect(resultado.esValida, isTrue, reason: telefono);
        expect(resultado.datos!.contactoEmergencia, telefono);
      }

      final vacio = validarFichaPaciente(
        nombre: 'Ana',
        edad: '',
        condicion: '',
        contactoEmergencia: '  ',
      );
      expect(vacio.esValida, isTrue);
      expect(vacio.datos!.contactoEmergencia, isNull);
    });

    test('rechaza menos de 7, más de 15 y caracteres no permitidos', () {
      for (final telefono in ['123456', '1234567890123456', '600-000-000']) {
        final resultado = validarFichaPaciente(
          nombre: 'Ana',
          edad: '',
          condicion: '',
          contactoEmergencia: telefono,
        );
        expect(resultado.esValida, isFalse, reason: telefono);
        expect(resultado.error, 'El teléfono debe tener entre 7 y 15 dígitos.');
      }
    });
  });

  group('condición', () {
    test('se recorta y admite hasta 80 caracteres', () {
      final alLimite = 'a' * condicionMaxCaracteres;
      final resultado = validarFichaPaciente(
        nombre: 'Ana',
        edad: '',
        condicion: '  $alLimite  ',
        contactoEmergencia: '',
      );

      expect(resultado.esValida, isTrue);
      expect(resultado.datos!.condicion, alLimite);
    });

    test('rechaza más de 80 caracteres', () {
      final resultado = validarFichaPaciente(
        nombre: 'Ana',
        edad: '',
        condicion: 'a' * (condicionMaxCaracteres + 1),
        contactoEmergencia: '',
      );

      expect(resultado.esValida, isFalse);
      expect(
        resultado.error,
        'La condición no puede superar los 80 caracteres.',
      );
    });
  });
}
