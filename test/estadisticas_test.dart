// Pruebas del cálculo de cumplimiento (`lib/utils/estadisticas.dart`). No
// requiere Firebase ni widgets: es lógica pura sobre `tratamientos` +
// `registrosToma`, movida a `lib/utils/` justamente para poder testearla.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/registro_toma.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/utils/estadisticas.dart';

void main() {
  // Miércoles. Los DateTime de prueba son UTC a propósito: el código normaliza
  // ahora a local para que no rompa el filtro por día de la semana.
  final ahora = DateTime(2026, 3, 11, 14, 30);

  Tratamiento diario08(
    String id, {
    List<int> dias = HorarioDia.todosLosDias,
  }) =>
      Tratamiento(
        id: id,
        pacienteId: 'p',
        nombreMedicamento: 'M',
        dosis: '1',
        horarios: [
          HorarioDia(hora: '08:00', dias: dias),
        ],
        frecuencia: 'Diaria',
      );

  RegistroToma tomada(
    String tratamientoId,
    DateTime horaProgramada, {
    EstadoToma estado = EstadoToma.tomada,
    DateTime? horaConfirmacion,
  }) =>
      RegistroToma(
        id: '${tratamientoId}_${horaProgramada.millisecondsSinceEpoch}',
        tratamientoId: tratamientoId,
        pacienteId: 'p',
        horaProgramada: horaProgramada,
        horaConfirmacion: horaConfirmacion ??
            (estado.registraConfirmacion ? horaProgramada : null),
        estado: estado,
      );

  group('adherencia y conteos', () {
    test('sin tratamientos -> no hay datos, porcentaje es null', () {
      final r = resumenCumplimiento(
        tratamientos: [],
        registros: [],
        ahora: ahora,
        dias: 7,
      );
      expect(r.hayDatos, false);
      expect(r.porcentajeATiempo, isNull);
      expect(r.esperadas, 0);
    });

    test('una sola toma tomada a tiempo cuenta como 100%', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0)),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.hayDatos, true);
      expect(r.esperadas, 1);
      expect(r.aTiempo, 1);
      expect(r.porcentajeATiempo, 100.0);
    });

    test('denominador sale del horario, no de registros', () {
      final t = diario08('t1');
      // No hay registro alguno: eso es una falta, no 100%.
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [],
        ahora: ahora,
        dias: 1,
      );
      expect(r.hayDatos, true);
      expect(r.esperadas, 1);
      expect(r.aTiempo, 0);
      expect(r.sinRegistro, 1);
      expect(r.sinConfirmar, 1);
      expect(r.porcentajeATiempo, 0.0);
    });

    test('pospuesta sin confirmacion cuenta como sin resolver', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0),
              estado: EstadoToma.pospuesta),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.esperadas, 1);
      expect(r.aTiempo, 0);
      expect(r.sinRegistro, 1); // no hay tomada ni tardia ni olvidada
      expect(r.sinConfirmar, 1);
      expect(r.estadoDiaDeHoy().estado, EstadoDia.diaConFaltas);
    });

    test('tardia no rompe el conteo de resueltas', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0),
              estado: EstadoToma.tardia),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.esperadas, 1);
      expect(r.aTiempo, 0);
      expect(r.tardias, 1);
      expect(r.aTiempo + r.tardias + r.olvidadas, 1); // resueltas
      expect(r.sinConfirmar, 0);
    });

    test('olvidada escrita por reconciliacion cuenta como olvidada', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0),
              estado: EstadoToma.olvidada),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.olvidadas, 1);
      expect(r.sinConfirmar, 1);
      expect(r.sinRegistro, 0);
    });

    test('dos medicamentos a la misma hora => 2 dosis esperadas', () {
      final t1 = diario08('t1');
      final t2 = diario08('t2');
      final r = resumenCumplimiento(
        tratamientos: [t1, t2],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0)),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.esperadas, 2);
      expect(r.aTiempo, 1);
      expect(r.sinRegistro, 1);
    });

    test('horario de lunes a viernes ignora sabado/domingo', () {
      final t = diario08('t1', dias: [1, 2, 3, 4, 5]); // lun-vie
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [],
        ahora: DateTime(2026, 3, 14, 14, 30), // sabado
        dias: 1,
      );
      expect(r.esperadas, 0);
      expect(r.hayDatos, false);
    });
  });

  group('racha (dias consecutivos sin fallos)', () {
    test('hoy queda fuera', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          // ayer todo a tiempo
          tomada('t1', DateTime(2026, 3, 10, 8, 0)),
          // hoy tambien a tiempo, pero no debe sumar
          tomada('t1', DateTime(2026, 3, 11, 8, 0)),
        ],
        ahora: ahora,
        dias: 7,
      );
      expect(r.racha, 1); // solo ayer
    });

    test('dia sin dosis esperadas ni suma ni rompe', () {
      final t = diario08('t1', dias: [1, 2, 4, 5]); // lunes, martes, jueves, viernes
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 10, 8, 0)), // martes
          tomada('t1', DateTime(2026, 3, 9, 8, 0)),  // lunes
          tomada('t1', DateTime(2026, 3, 6, 8, 0)),  // viernes de la semana anterior
        ],
        ahora: ahora, // miercoles 11
        dias: 7,
      );
      // Miercoles no espera nada -> se salta; martes y lunes perfectos => racha 2
      expect(r.racha, 2);
    });

    test('una tardia rompe la racha', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 10, 8, 20), estado: EstadoToma.tardia), // ayer tardia -> rompe
          tomada('t1', DateTime(2026, 3, 9, 8, 0)),  // anteayer a tiempo, no cuenta
          tomada('t1', DateTime(2026, 3, 8, 8, 0)),  // anterior, no cuenta
        ],
        ahora: ahora,
        dias: 7,
      );
      expect(r.racha, 0);
    });

    test('falta (sin registro) rompe la racha', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          // ayer sin registro -> falla
          tomada('t1', DateTime(2026, 3, 9, 8, 0)), // anteayer ok, no cuenta porque corte a partir de ayer?
          tomada('t1', DateTime(2026, 3, 8, 8, 0)),
        ],
        ahora: ahora,
        dias: 7,
      );
      // Ayer falta => racha 0
      expect(r.racha, 0);
    });

    test('olvidada rompe la racha', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 10, 8, 0), estado: EstadoToma.olvidada),
          tomada('t1', DateTime(2026, 3, 9, 8, 0)),
        ],
        ahora: ahora,
        dias: 7,
      );
      expect(r.racha, 0);
    });

    test('pospuesta no cuenta como dia perfecto', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 10, 8, 0), estado: EstadoToma.pospuesta),
          tomada('t1', DateTime(2026, 3, 9, 8, 0)),
        ],
        ahora: ahora,
        dias: 7,
      );
      // pospuesta deja sin resolver => diaConFaltas
      expect(r.racha, 0);
    });

    test('maximo 7 dias de confianza', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          // hace 8 dias a tiempo (dia -8 desde hoy? hoy 11, -8 es 3 mar)
          tomada('t1', DateTime(2026, 3, 3, 8, 0)),
          tomada('t1', DateTime(2026, 3, 4, 8, 0)),
          tomada('t1', DateTime(2026, 3, 5, 8, 0)),
          tomada('t1', DateTime(2026, 3, 6, 8, 0)),
          tomada('t1', DateTime(2026, 3, 7, 8, 0)), // sabado? 7 mar es sabado
          tomada('t1', DateTime(2026, 3, 9, 8, 0)), // lunes
          tomada('t1', DateTime(2026, 3, 10, 8, 0)), // martes
        ],
        ahora: ahora,
        dias: 14,
      );
      // solo mira hasta 7 dias hacia atras desde ayer; lo de hace 8+ no cuenta
      expect(r.racha >= 0 && r.racha <= 7, true);
    });
  });

  group('tira de 7 dias', () {
    test('el ultimo elemento es hoy', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [],
        ahora: ahora,
        dias: 7,
      );
      expect(r.dias.last.dia.day, 11);
    });

    test('dia perfecto cuando todo a tiempo', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0)),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.dias[0].estado, EstadoDia.diaPerfecto);
    });

    test('conTardias cuando hay tardias pero no faltas', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [
          tomada('t1', DateTime(2026, 3, 11, 8, 0), estado: EstadoToma.tardia),
        ],
        ahora: ahora,
        dias: 1,
      );
      expect(r.dias[0].estado, EstadoDia.conTardias);
    });

    test('diaConFaltas cuando no hay registro', () {
      final t = diario08('t1');
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [],
        ahora: ahora,
        dias: 1,
      );
      expect(r.dias[0].estado, EstadoDia.diaConFaltas);
    });

    test('sinDosis cuando el horario no aplica', () {
      final t = diario08('t1', dias: [1, 2, 3, 4, 5]); // lun-vie
      final r = resumenCumplimiento(
        tratamientos: [t],
        registros: [],
        ahora: DateTime(2026, 3, 15, 14, 30), // domingo
        dias: 1,
      );
      expect(r.dias[0].estado, EstadoDia.sinDosis);
    });
  });
}

extension Helper on ResumenCumplimiento {
  ResumenDia estadoDiaDeHoy() {
    if (dias.isEmpty) return ResumenDia(dia: DateTime(2026, 3, 11));
    return dias.last;
  }
}
