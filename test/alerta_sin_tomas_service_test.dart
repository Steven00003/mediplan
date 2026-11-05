// Pruebas puras de la alerta de 5 días sin tomas.
//
// No usan Firebase: la reconciliación y el detalle del cuidador solo llaman a
// AlertaSinTomasService.hayAlerta con tratamientos y registros ya leídos.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/registro_toma.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/services/alerta_sin_tomas_service.dart';

const _todosLosDias = [1, 2, 3, 4, 5, 6, 7];

Tratamiento _tratamiento({
  required DateTime? inicio,
  List<HorarioDia> horarios = const [
    HorarioDia(hora: '08:00', dias: _todosLosDias),
  ],
  int? duracionDias,
  String id = 't1',
}) {
  return Tratamiento(
    id: id,
    pacienteId: 'p1',
    nombreMedicamento: 'Medicamento',
    dosis: '1',
    horarios: horarios,
    frecuencia: 'Diaria',
    fechaInicio: inicio,
    duracionDias: duracionDias,
  );
}

RegistroToma _registro(
  String tratamientoId,
  DateTime horaProgramada, {
  EstadoToma estado = EstadoToma.tomada,
  DateTime? horaConfirmacion,
}) {
  return RegistroToma(
    id: '${tratamientoId}_${horaProgramada.millisecondsSinceEpoch}',
    tratamientoId: tratamientoId,
    pacienteId: 'p1',
    horaProgramada: horaProgramada,
    horaConfirmacion: horaConfirmacion,
    estado: estado,
  );
}

void main() {
  // Jueves 5 de noviembre de 2026.
  final ahora = DateTime(2026, 11, 5, 12);
  final inicioLargo = DateTime(2026, 10, 26);

  group('AlertaSinTomasService.hayAlerta', () {
    test('los días sin horario se saltan y no cuentan como días sin toma', () {
      // Lunes 28/09/2026. Antes del jueves 05/11 hay 5 lunes programados:
      // 05, 12, 19 y 26 de octubre y 02 de noviembre.
      final tratamiento = _tratamiento(
        inicio: DateTime(2026, 9, 28),
        horarios: const [
          HorarioDia(hora: '08:00', dias: [1]),
        ],
      );

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: const [],
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('un tratamiento nuevo con menos de 5 días programados no dispara', () {
      final tratamiento = _tratamiento(inicio: DateTime(2026, 11, 2));

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: const [],
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('un tratamiento terminado no dispara', () {
      final tratamiento = _tratamiento(
        inicio: DateTime(2026, 10, 26),
        duracionDias: 5,
      );

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: const [],
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('una toma confirmada rompe la racha', () {
      final tratamiento = _tratamiento(inicio: inicioLargo);
      final registros = [
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 2, 8),
          horaConfirmacion: DateTime(2026, 11, 2, 8, 5),
        ),
      ];

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: registros,
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('una toma tardía también rompe la racha', () {
      final tratamiento = _tratamiento(inicio: inicioLargo);
      final registros = [
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 3, 8),
          estado: EstadoToma.tardia,
          horaConfirmacion: DateTime(2026, 11, 3, 9),
        ),
      ];

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: registros,
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('solo olvidadas (y pospuestas) no rompen la racha', () {
      final tratamiento = _tratamiento(inicio: inicioLargo);
      final registros = [
        _registro(
          tratamiento.id,
          DateTime(2026, 10, 31, 8),
          estado: EstadoToma.olvidada,
        ),
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 1, 8),
          estado: EstadoToma.pospuesta,
          horaConfirmacion: DateTime(2026, 11, 1, 8, 1),
        ),
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 2, 8),
          estado: EstadoToma.olvidada,
        ),
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 3, 8),
          estado: EstadoToma.olvidada,
        ),
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 4, 8),
          estado: EstadoToma.olvidada,
        ),
      ];

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: registros,
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('inicio desconocido no dispara', () {
      final tratamiento = _tratamiento(inicio: null);

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: const [],
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('menos de 5 días programados desde el inicio no dispara', () {
      // Lunes 12/10/2026: solo hay 4 lunes antes del jueves 05/11.
      final tratamiento = _tratamiento(
        inicio: DateTime(2026, 10, 12),
        horarios: const [
          HorarioDia(hora: '08:00', dias: [1]),
        ],
      );

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: const [],
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('el cambio de día a medianoche mueve la ventana', () {
      final tratamiento = _tratamiento(inicio: inicioLargo);
      final registros = [
        // La toma de hoy se confirma, pero hoy todavía no cuenta.
        _registro(
          tratamiento.id,
          DateTime(2026, 11, 5, 8),
          horaConfirmacion: DateTime(2026, 11, 5, 8, 5),
        ),
      ];

      final antesDeMedianoche = DateTime(2026, 11, 5, 23, 59);
      final despuesDeMedianoche = DateTime(2026, 11, 6, 0, 1);

      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: registros,
          ahora: antesDeMedianoche,
        ),
        isTrue,
      );
      expect(
        AlertaSinTomasService.hayAlerta(
          tratamiento: tratamiento,
          registros: registros,
          ahora: despuesDeMedianoche,
        ),
        isFalse,
      );
    });
  });
}
