// Pruebas de `resumenHorario`, el formateo del horario de un tratamiento para la
// tarjeta del detalle del paciente. No requiere Firebase ni widgets: es lógica
// de presentación pura, movida a `lib/utils/resumen_horario.dart` justamente
// para poder testearla (antes vivía como método privado de la pantalla).
//
// El contrato que se fija aquí es el de "una sola línea de días" vs "los días
// pegados a cada hora", que es donde un cambio silencioso se notaría en la UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/utils/resumen_horario.dart';

void main() {
  Tratamiento conHoras(List<HorarioDia> horarios) => Tratamiento(
        id: 't1',
        pacienteId: 'p1',
        nombreMedicamento: 'Paracetamol',
        dosis: '1',
        horarios: horarios,
        frecuencia: 'Diaria',
      );

  group('resumenHorario', () {
    test('días compartidos: horas sueltas y los días en la 2ª línea', () {
      final (horas, dias) = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [1, 3, 5]),
        HorarioDia(hora: '20:00', dias: [1, 3, 5]),
      ]));

      // No se repite "Lun · Mié · Vie" en cada hora.
      expect(horas, '08:00 / 20:00');
      expect(dias, 'Lun · Mié · Vie');
    });

    test('días distintos: cada hora lleva los suyos y no hay 2ª línea', () {
      final (horas, dias) = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [1, 3, 5]),
        HorarioDia(hora: '20:00', dias: [2, 4]),
      ]));

      expect(horas, '08:00 (Lun · Mié · Vie) / 20:00 (Mar · Jue)');
      expect(dias, '');
    });

    test('diario (7 días) mezclado con uno específico: sin paréntesis vacío', () {
      final (horas, dias) = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [1, 3, 5]),
        HorarioDia(
            hora: '20:00', dias: HorarioDia.todosLosDias),
      ]));

      expect(horas, '08:00 (Lun · Mié · Vie) / 20:00');
      expect(dias, '');
    });

    test('horarios vacíos devuelve las dos cadenas vacías', () {
      expect(resumenHorario(conHoras(const [])), ('', ''));
    });

    test('el orden de los días no importa', () {
      final ordenado = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [1, 3, 5]),
      ]));
      final desordenado = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [5, 1, 3]),
      ]));

      expect(ordenado, desordenado);
      expect(ordenado.$2, 'Lun · Mié · Vie');
    });

    test('el orden no importa ni al decidir que los días están compartidos', () {
      final a = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [1, 3, 5]),
        HorarioDia(hora: '20:00', dias: [5, 3, 1]),
      ]));
      final b = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [5, 1, 3]),
        HorarioDia(hora: '20:00', dias: [1, 5, 3]),
      ]));

      expect(a, b);
      expect(a.$1, '08:00 / 20:00');
      expect(a.$2, 'Lun · Mié · Vie');
    });

    test('un solo horario: días en la 2ª línea (nada que comparar)', () {
      final (horas, dias) =
          resumenHorario(conHoras(const [HorarioDia(hora: '09:00', dias: [6, 7])]));

      expect(horas, '09:00');
      expect(dias, 'Sáb · Dom');
    });

    test('tratamiento diario completo no muestra línea de días', () {
      final (horas, dias) = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '20:00', dias: HorarioDia.todosLosDias),
      ]));

      expect(horas, '08:00 / 20:00');
      expect(dias, '');
    });

    test('lista de días vacía no produce paréntesis ni texto "?"', () {
      final (horas, dias) = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [1, 3]),
        HorarioDia(hora: '20:00', dias: []),
      ]));

      expect(horas, '08:00 (Lun · Mié) / 20:00');
      expect(dias, '');
    });

    test('los días siempre salen ordenados de lunes a domingo', () {
      final (_, dias) = resumenHorario(conHoras(const [
        HorarioDia(hora: '08:00', dias: [7, 1, 4]),
      ]));

      expect(dias, 'Lun · Jue · Dom');
    });
  });
}
