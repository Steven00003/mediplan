import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/medico.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/utils/medico_tratamiento.dart';
import 'package:mediplan/utils/validacion_perfil_medico.dart';

String _foto(int bytes) =>
    'data:image/jpeg;base64,${base64Encode(List<int>.filled(bytes, 1))}';

void main() {
  group('validarPerfilMedico', () {
    test('acepta un perfil válido', () {
      expect(
        validarPerfilMedico(
          nombre: 'Dra. Pérez',
          titulo: 'Medicina general',
          especialidad: 'Pediatría',
        ),
        isEmpty,
      );
    });

    test('exige nombre y respeta longitudes', () {
      final errores = validarPerfilMedico(
        nombre: '',
        titulo: 'x' * 121,
        especialidad: 'y' * 81,
      );
      expect(errores['nombre'], isNotNull);
      expect(errores['titulo'], isNotNull);
      expect(errores['especialidad'], isNotNull);
    });

    test('rechaza foto mayor a 60 KB', () {
      final errores = validarPerfilMedico(
        nombre: 'Dra. Pérez',
        titulo: '',
        especialidad: '',
        fotoBase64: _foto(60 * 1024 + 1),
      );
      expect(errores['fotoBase64'], isNotNull);
    });

    test('acepta foto de 60 KB y rechaza datos no base64', () {
      expect(
        validarPerfilMedico(
          nombre: 'Dra. Pérez',
          titulo: '',
          especialidad: '',
          fotoBase64: _foto(60 * 1024),
        ),
        isEmpty,
      );
      expect(
        validarPerfilMedico(
          nombre: 'Dra. Pérez',
          titulo: '',
          especialidad: '',
          fotoBase64: 'data:image/jpeg;base64,@@@',
        )['fotoBase64'],
        isNotNull,
      );
    });
  });

  group('idMedicoRecetador', () {
    Tratamiento tratamiento({String? recetadoPorId}) => Tratamiento(
      id: 't1',
      pacienteId: 'p1',
      nombreMedicamento: 'Paracetamol',
      dosis: '1',
      horarios: const [],
      frecuencia: '',
      recetadoPorId: recetadoPorId,
    );

    test('usa recetadoPorId cuando existe', () {
      expect(
        idMedicoRecetador(
          tratamiento(recetadoPorId: 'medico-nuevo'),
          'cuidador-viejo',
        ),
        'medico-nuevo',
      );
    });

    test('cae al cuidadorId en tratamientos antiguos', () {
      expect(
        idMedicoRecetador(tratamiento(), 'cuidador-viejo'),
        'cuidador-viejo',
      );
      expect(idMedicoRecetador(tratamiento(), null), isNull);
    });
  });

  test('Medico.fromMap lee el perfil', () {
    final medico = Medico.fromMap('uid-1', {
      'nombre': 'Dra. Pérez',
      'titulo': 'Medicina',
      'especialidad': 'Pediatría',
    });
    expect(medico.nombre, 'Dra. Pérez');
    expect(medico.especialidad, 'Pediatría');
  });
}
