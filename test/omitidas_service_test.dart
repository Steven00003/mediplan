// Pruebas de la enumeración de ranuras y del cálculo de "tomas olvidadas".
//
// Son funciones puras (`OmitidasService.ranurasDelDia` / `ranurasVencidas` /
// `clavesResueltas` / `idDocumento`), sin Firebase ni widgets: por eso se puede
// fijar aquí toda la lógica que decide a quién se le marca una toma como perdida.
//
// Lo que se fija, en orden de importancia:
//  - que un horario con días no genere tomas en los días que no toca (si no,
//    se inventarían faltas que nuncatocaron la hora),
//  - que dos medicamentos a la misma hora no se marquen mutuamente,
//  - que la última toma del período no venza (no hay "siguiente" que la venciera),
//  - que un `pospuesta` no cierre la cuenta y una tomada sí.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/registro_toma.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/services/omitidas_service.dart';

/// 2024-03-11 es lunes; los tests se apoyan en que hoy sea lunes.
final _lunes = DateTime(2024, 3, 11);
final _martes = DateTime(2024, 3, 12);
final _miercoles = DateTime(2024, 3, 13);

Tratamiento _tratamiento(
  String id,
  List<HorarioDia> horarios, {
  String nombre = 'Paracetamol',
}) {
  return Tratamiento(
    id: id,
    pacienteId: 'p1',
    nombreMedicamento: nombre,
    dosis: '1',
    horarios: horarios,
    frecuencia: 'Diaria',
  );
}

RegistroToma _registro(
  String tratamientoId,
  DateTime horaProgramada,
  EstadoToma estado,
) {
  return RegistroToma(
    id: 'x',
    tratamientoId: tratamientoId,
    pacienteId: 'p1',
    horaProgramada: horaProgramada,
    estado: estado,
  );
}

void main() {
  final diario = _tratamiento('t1', const [
    HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias)
  ]);

  group('EstadoToma', () {
    test('esTerminal: solo la resuelve una toma que ya no espera nada más', () {
      expect(EstadoToma.tomada.esTerminal, isTrue);
      expect(EstadoToma.tardia.esTerminal, isTrue);
      expect(EstadoToma.olvidada.esTerminal, isTrue);
      // Posponer reagenda el aviso, así que sigue abierto.
      expect(EstadoToma.pospuesta.esTerminal, isFalse);
      expect(EstadoToma.pendiente.esTerminal, isFalse);
    });

    test('registraConfirmacion: una toma olvidada no lleva hora de confirmación', () {
      expect(EstadoToma.tomada.registraConfirmacion, isTrue);
      expect(EstadoToma.tardia.registraConfirmacion, isTrue);
      // "Olvidada" ES una toma que nunca se confirmó: sellarle una hora mentiría.
      expect(EstadoToma.olvidada.registraConfirmacion, isFalse);
      expect(EstadoToma.pendiente.registraConfirmacion, isFalse);
    });
  });

  group('ranurasDelDia', () {
    test('un horario diario produce su ranura ese día', () {
      final ranuras = OmitidasService.ranurasDelDia([diario], _lunes);

      expect(ranuras.length, 1);
      expect(ranuras.first.tratamientoId, 't1');
      expect(ranuras.first.horaProgramada, DateTime(2024, 3, 11, 8, 0));
    });

    test('respeta los días de la semana: lunes aplica, martes no', () {
      final soloLunes = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: [1])
      ]);

      expect(OmitidasService.ranurasDelDia([soloLunes], _lunes).length, 1);
      expect(OmitidasService.ranurasDelDia([soloLunes], _martes).isEmpty, isTrue);
      expect(
          OmitidasService.ranurasDelDia([soloLunes], _miercoles).isEmpty, isTrue);
    });

    test('varios tratamientos y horarios generan todas sus ranuras', () {
      final t1 = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '20:00', dias: HorarioDia.todosLosDias),
      ]);
      final t2 = _tratamiento('t2', const [
        HorarioDia(hora: '13:00', dias: HorarioDia.todosLosDias)
      ]);

      final ranuras = OmitidasService.ranurasDelDia([t1, t2], _lunes);

      expect(ranuras.length, 3);
      expect(
        ranuras.map((r) => '${r.tratamientoId}@${r.horaProgramada.hour}').toSet(),
        {'t1@8', 't1@20', 't2@13'},
      );
    });

    test('deduplica horas solapadas del mismo tratamiento', () {
      // El editor permite guardar dos entradas con la misma hora y días que se
      // pisan: describen la misma ranura y no pueden generar dos faltas.
      final solapado = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: [1, 2]),
        HorarioDia(hora: '08:00', dias: [2, 3]),
      ]);

      final martes = OmitidasService.ranurasDelDia([solapado], _martes);

      expect(martes.length, 1);
    });

    test('ignora horas mal formadas y una lista de días vacía', () {
      final raro = _tratamiento('t1', const [
        HorarioDia(hora: '8', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: 'noche', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '99:99', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '10:00', dias: []),
      ]);

      expect(OmitidasService.ranurasDelDia([raro], _lunes).isEmpty, isTrue);
    });
  });

  group('ranurasVencidas', () {
    test('no vence nada si solo hay una toma en todo el período', () {
      // Sin una toma posterior no hay "siguiente medicamento" que venza.
      // Se limita a un día para que la única ranura sea la de hoy.
      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [diario],
        ahora: DateTime(2024, 3, 11, 23, 0),
        diasAtras: 1,
      );

      expect(vencidas.isEmpty, isTrue);
    });

    test('la toma anterior vence cuando llega la siguiente', () {
      final t1 = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '20:00', dias: HorarioDia.todosLosDias),
      ]);

      // 19:00: llegó la primera hora pero no la de las 20:00 → nada vencido.
      expect(
        OmitidasService.ranurasVencidas(
            tratamientos: [t1],
            ahora: DateTime(2024, 3, 11, 19, 0),
            diasAtras: 1)
            .isEmpty,
        isTrue,
      );

      // 20:00 en punto: ya llegó el siguiente, la de las 08:00 venció.
      final vencidas = OmitidasService.ranurasVencidas(
          tratamientos: [t1],
          ahora: DateTime(2024, 3, 11, 20, 0),
          diasAtras: 1);
      expect(vencidas.length, 1);
      expect(vencidas.first.horaProgramada, DateTime(2024, 3, 11, 8, 0));
    });

    test('una toma futura no vence nunca', () {
      // Hay dos días de historial: la de ayer solo vencería cuando llegara la
      // de hoy, que todavía no ha llegado.
      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [diario],
        ahora: DateTime(2024, 3, 11, 6, 0),
        diasAtras: 2,
      );

      expect(vencidas.isEmpty, isTrue);
    });

    test('dos medicamentos a la misma hora no se vencen mutuamente', () {
      // Si se vincieran entre sí, una toma quedaría "olvidada" en el instante
      // exacto en que vencía, compitiendo con su propia alarma.
      final a = _tratamiento('ta', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias)
      ]);
      final b = _tratamiento('tb', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias)
      ]);

      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [a, b],
        ahora: DateTime(2024, 3, 11, 8, 0),
        diasAtras: 1,
      );

      expect(vencidas.isEmpty, isTrue);
    });

    test('con dos medicamentos a la misma hora, vence cuando llega OTRO después', () {
      final a = _tratamiento('ta', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias)
      ]);
      final b = _tratamiento('tb', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias)
      ]);
      final c = _tratamiento('tc', const [
        HorarioDia(hora: '20:00', dias: HorarioDia.todosLosDias)
      ]);

      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [a, b, c],
        ahora: DateTime(2024, 3, 11, 20, 0),
        diasAtras: 1,
      );

      // Las DOS de las 08:00 quedan pendientes; la de las 20:00 no (es la última).
      expect(vencidas.length, 2);
      expect(vencidas.every((r) => r.horaProgramada.hour == 8), isTrue);
    });

    test('no inventa faltas en días que el horario no cubre', () {
      // Solo lunes: el martes no debe generar nada, ni hoy ni en el backfill.
      final soloLunes = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: [1])
      ]);

      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [soloLunes],
        ahora: DateTime(2024, 3, 11, 23, 0),
      );

      expect(vencidas.every((r) => r.horaProgramada.weekday == 1), isTrue);
      expect(vencidas.every((r) => r.horaProgramada.day == 11), isTrue);
    });

    test('el backfill cubre los 7 días anteriores incluido el actual', () {
      final t1 = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '20:00', dias: HorarioDia.todosLosDias),
      ]);

      // Martes 13 a las 21:00. Deberían estar vencidas todas las 08:00 y las
      // 20:00 del rango de 7 días, menos la última (la de hoy a las 20:00).
      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [t1],
        ahora: DateTime(2024, 3, 13, 21, 0),
      );

      final dias = vencidas.map((r) => r.horaProgramada.day).toSet();
      expect(dias.length, 7, reason: 'debe alcanzar los 7 días hacia atrás');
      expect(dias.contains(13), isTrue, reason: 'incluye el día actual');
      expect(dias.contains(7), isTrue, reason: 'incluye 7 días atrás');
    });

    test('el backfill nunca mira más atrás de la ventana', () {
      final t1 = _tratamiento('t1', const [
        HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias),
        HorarioDia(hora: '20:00', dias: HorarioDia.todosLosDias),
      ]);

      final vencidas = OmitidasService.ranurasVencidas(
        tratamientos: [t1],
        ahora: DateTime(2024, 3, 13, 21, 0),
        diasAtras: 3,
      );

      expect(
        vencidas.every((r) =>
            r.horaProgramada.isAfter(DateTime(2024, 3, 10, 23, 59))),
        isTrue,
      );
    });
  });

  group('clavesResueltas', () {
    final ranura = DateTime(2024, 3, 11, 8, 0);

    test('tomó, tardó y olvidada cierran la cuenta de la ranura', () {
      for (final estado in [
        EstadoToma.tomada,
        EstadoToma.tardia,
        EstadoToma.olvidada
      ]) {
        expect(
          OmitidasService.clavesResueltas([_registro('t1', ranura, estado)])
              .contains(RanuraToma(tratamientoId: 't1', horaProgramada: ranura).clave),
          isTrue,
          reason: '$estado debería resolver la ranura',
        );
      }
    });

    test('pospuesta NO cierra la cuenta: se reagendó, sigue sin resolverse', () {
      expect(
        OmitidasService.clavesResueltas(
            [_registro('t1', ranura, EstadoToma.pospuesta)]),
        isEmpty,
      );
      expect(
        OmitidasService.clavesResueltas(
            [_registro('t1', ranura, EstadoToma.pendiente)]),
        isEmpty,
      );
    });

    test('el resultado está indexado por tratamiento + hora exacta', () {
      final claves = OmitidasService.clavesResueltas([
        _registro('t1', ranura, EstadoToma.tomada),
        _registro('t2', ranura, EstadoToma.tomada),
        _registro('t1', DateTime(2024, 3, 11, 20, 0), EstadoToma.tomada),
      ]);

      expect(claves.length, 3);
      expect(
        claves.contains(
            RanuraToma(tratamientoId: 't1', horaProgramada: ranura).clave),
        isTrue,
      );
      expect(
        claves.contains(
            RanuraToma(tratamientoId: 't2', horaProgramada: ranura).clave),
        isTrue,
      );
      // Otra hora del mismo tratamiento es otra ranura.
      expect(
        claves.contains(RanuraToma(
                tratamientoId: 't1', horaProgramada: DateTime(2024, 3, 11, 20))
            .clave),
        isTrue,
      );
    });
  });

  group('idDocumento', () {
    test('la misma ranura produce siempre el mismo id', () {
      final ranura = DateTime(2024, 3, 11, 8, 0);

      expect(
        OmitidasService.idDocumento('t1', ranura),
        OmitidasService.idDocumento('t1', ranura),
      );
    });

    test('ranuras distintas producen ids distintos (idempotencia sin choques)', () {
      final ids = {
        OmitidasService.idDocumento('t1', DateTime(2024, 3, 11, 8)),
        OmitidasService.idDocumento('t1', DateTime(2024, 3, 11, 20)),
        OmitidasService.idDocumento('t2', DateTime(2024, 3, 11, 8)),
        OmitidasService.idDocumento('t1', DateTime(2024, 3, 12, 8)),
      };

      expect(ids.length, 4);
    });

    test('el id nunca es el 0 reservado ni vacío', () {
      for (final d in [1, 8, 11, 18, 25]) {
        for (final t in ['t1', 't2', 'un-id-muy-largo']) {
          final id = OmitidasService.idDocumento(t, DateTime(2024, 3, d, 8));
          expect(id, isNotEmpty);
          expect(int.parse(id), isNot(0));
        }
      }
    });
  });
}