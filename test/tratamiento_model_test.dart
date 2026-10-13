// Pruebas del modelo Tratamiento/HorarioDia. No requieren Firebase: solo
// ejercitan fromMap/toMap, incluida la compatibilidad con documentos antiguos
// cuyos `horarios` eran una lista de strings sin días.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/tratamiento.dart';

void main() {
  group('Tratamiento.horarios', () {
    test('lee el formato viejo (List<String>) y asume todos los días', () {
      final t = Tratamiento.fromMap('id1', {
        'pacienteId': 'p1',
        'nombreMedicamento': 'Paracetamol',
        'dosis': '1',
        'horarios': ['08:00', '20:00'],
        'frecuencia': 'Diaria',
      });

      expect(t.horarios.length, 2);
      expect(t.horarios[0].hora, '08:00');
      expect(t.horarios[1].hora, '20:00');
      expect(t.horarios[0].dias, HorarioDia.todosLosDias);
      expect(t.horarios[1].dias, HorarioDia.todosLosDias);
    });

    test('lee el formato nuevo respetando los días', () {
      final t = Tratamiento.fromMap('id1', {
        'nombreMedicamento': 'Ibuprofeno',
        'horarios': [
          {'hora': '09:00', 'dias': [1, 3, 5]},
          {'hora': '21:00', 'dias': [2, 4]},
        ],
      });

      expect(t.horarios.length, 2);
      expect(t.horarios[0].hora, '09:00');
      expect(t.horarios[0].dias, [1, 3, 5]);
      expect(t.horarios[1].hora, '21:00');
      expect(t.horarios[1].dias, [2, 4]);
    });

    test('si un mapa nuevo no trae `dias`, se asume diario', () {
      final t = Tratamiento.fromMap('id1', {
        'nombreMedicamento': 'X',
        'horarios': [
          {'hora': '07:30'},
        ],
      });

      expect(t.horarios.single.dias, HorarioDia.todosLosDias);
    });

    test('toMap siempre escribe el formato nuevo {hora, dias}', () {
      final t = Tratamiento.fromMap('id1', {
        'nombreMedicamento': 'X',
        'horarios': ['08:00'],
      });

      expect(t.toMap()['horarios'], [
        {
          'hora': '08:00',
          'dias': HorarioDia.todosLosDias,
        },
      ]);
    });

    test('horarios ausente o de tipo inesperado produce lista vacía', () {
      final sinCampo = Tratamiento.fromMap('id', {'nombreMedicamento': 'X'});
      final tipoRaro = Tratamiento.fromMap(
          'id', {'nombreMedicamento': 'X', 'horarios': '08:00'});

      expect(sinCampo.horarios, isEmpty);
      expect(tipoRaro.horarios, isEmpty);
    });

    test('ida y vuelta: formato viejo -> nuevo no pierde horas', () {
      final viejo = Tratamiento.fromMap('id1', {
        'nombreMedicamento': 'X',
        'horarios': ['08:00', '20:00'],
      });

      final releido = Tratamiento.fromMap('id1', viejo.toMap());

      expect(releido.horarios.map((h) => h.hora).toList(), ['08:00', '20:00']);
      expect(releido.horarios.every((h) => h.dias.length == 7), isTrue);
    });
  });
}
