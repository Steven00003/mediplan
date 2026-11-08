// Pruebas puras de la identidad de una ranura y de la deduplicación de
// registros. No usan Firebase: fijan el criterio que comparten el historial,
// las estadísticas y la comprobación de una dosis ya registrada.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/registro_toma.dart';
import 'package:mediplan/services/omitidas_service.dart';
import 'package:mediplan/utils/id_ranura.dart';
import 'package:mediplan/utils/registros_toma.dart';

RegistroToma _registro(
  String id, {
  String tratamientoId = 't1',
  required DateTime hora,
  required EstadoToma estado,
  DateTime? horaConfirmacion,
}) => RegistroToma(
  id: id,
  tratamientoId: tratamientoId,
  pacienteId: 'p1',
  horaProgramada: hora,
  horaConfirmacion: horaConfirmacion,
  estado: estado,
);

void main() {
  final hora = DateTime.utc(2024, 3, 11, 8);

  group('ranura cerrada por estado', () {
    test('tomó, tardó y olvidó cierran; pospuesta y pendiente no', () {
      expect(RegistrosToma.esFinal(EstadoToma.tomada), isTrue);
      expect(RegistrosToma.esFinal(EstadoToma.tardia), isTrue);
      expect(RegistrosToma.esFinal(EstadoToma.olvidada), isTrue);
      expect(RegistrosToma.esFinal(EstadoToma.pospuesta), isFalse);
      expect(RegistrosToma.esFinal(EstadoToma.pendiente), isFalse);
    });

    test('una pospuesta sola no cierra la ranura', () {
      final pospuesta = _registro(
        'p',
        hora: hora,
        estado: EstadoToma.pospuesta,
        horaConfirmacion: hora,
      );

      expect(
        RegistrosToma.finalDeRanura(
          [pospuesta],
          tratamientoId: 't1',
          horaProgramada: hora,
        ),
        isNull,
      );
    });

    test('un terminal gana sobre una pospuesta', () {
      final pospuesta = _registro(
        'p',
        hora: hora,
        estado: EstadoToma.pospuesta,
        horaConfirmacion: hora,
      );
      final tomada = _registro(
        't',
        hora: hora,
        estado: EstadoToma.tomada,
        horaConfirmacion: hora.add(const Duration(minutes: 3)),
      );

      expect(
        RegistrosToma.finalDeRanura(
          [pospuesta, tomada],
          tratamientoId: 't1',
          horaProgramada: hora,
        )?.id,
        't',
      );
    });
  });

  group('deduplicación por ranura', () {
    test('conserva la primera confirmación de la misma ranura', () {
      final segunda = _registro(
        'segunda',
        hora: hora,
        estado: EstadoToma.tomada,
        horaConfirmacion: hora.add(const Duration(minutes: 10)),
      );
      final primera = _registro(
        'primera',
        hora: hora,
        estado: EstadoToma.tomada,
        horaConfirmacion: hora.add(const Duration(minutes: 2)),
      );

      final unicos = RegistrosToma.deduplicarPorRanura([segunda, primera]);

      expect(unicos, hasLength(1));
      expect(unicos.single.id, 'primera');
    });

    test('una confirmación gana sobre una olvidada de la misma ranura', () {
      final olvidada = _registro(
        'olvidada',
        hora: hora,
        estado: EstadoToma.olvidada,
      );
      final tomada = _registro(
        'tomada',
        hora: hora,
        estado: EstadoToma.tomada,
        horaConfirmacion: hora.add(const Duration(minutes: 5)),
      );

      final unicos = RegistrosToma.deduplicarPorRanura([olvidada, tomada]);

      expect(unicos.single.id, 'tomada');
    });

    test('ranuras distintas se conservan por separado', () {
      final otraHora = hora.add(const Duration(hours: 12));
      final unicos = RegistrosToma.deduplicarPorRanura([
        _registro('a', hora: hora, estado: EstadoToma.tomada),
        _registro('b', hora: otraHora, estado: EstadoToma.tomada),
        _registro('a2', hora: hora, estado: EstadoToma.tomada),
      ]);

      expect(unicos, hasLength(2));
      expect(unicos.map((r) => r.id), orderedEquals(['a', 'b']));
    });
  });

  group('id determinista de la ranura', () {
    test('es estable y comparte esquema con las tomas olvidadas', () {
      // Literal fijado a propósito: si cambia `hashEstable` o el prefijo, los
      // ids de las tomas olvidadas ya escritas dejarían de coincidir.
      expect(idDocumentoDeRanura('t1', hora), '503251628');
      expect(
        OmitidasService.idDocumento('t1', hora),
        idDocumentoDeRanura('t1', hora),
      );
      expect(
        idDocumentoDeRanura('t1', hora),
        idDocumentoDeRanura('t1', hora),
      );
      expect(
        idDocumentoDeRanura('t2', hora),
        isNot(idDocumentoDeRanura('t1', hora)),
      );
      expect(
        idDocumentoDeRanura('t1', hora.add(const Duration(hours: 1))),
        isNot(idDocumentoDeRanura('t1', hora)),
      );
    });
  });
}
