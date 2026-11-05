// Pruebas puras de la vigencia de un tratamiento: fecha de fin inclusive,
// días restantes y texto para el paciente.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/utils/vigencia_tratamiento.dart';

Tratamiento _tratamiento({DateTime? fechaInicio, int? duracionDias}) {
  return Tratamiento(
    id: 't1',
    pacienteId: 'p1',
    nombreMedicamento: 'Paracetamol',
    dosis: '1',
    horarios: const [HorarioDia(hora: '08:00', dias: HorarioDia.todosLosDias)],
    frecuencia: 'Diaria',
    fechaInicio: fechaInicio,
    duracionDias: duracionDias,
  );
}

void main() {
  group('VigenciaTratamiento', () {
    test('continuo: vigente y sin fecha de fin ni texto', () {
      final t = _tratamiento(
        fechaInicio: DateTime(2026, 11, 2),
        duracionDias: null,
      );
      final ahora = DateTime(2030, 1, 1, 12);

      expect(VigenciaTratamiento.fechaFin(t), isNull);
      expect(VigenciaTratamiento.estaVigente(t, ahora), isTrue);
      expect(VigenciaTratamiento.diasRestantes(t, ahora), isNull);
      expect(VigenciaTratamiento.textoParaPaciente(t, ahora), isNull);
    });

    test('inicio desconocido: no calcula fin, pero sigue activo', () {
      final t = _tratamiento(fechaInicio: null, duracionDias: 7);
      final ahora = DateTime(2026, 11, 2);

      expect(VigenciaTratamiento.fechaFin(t), isNull);
      expect(VigenciaTratamiento.estaVigente(t, ahora), isTrue);
      expect(VigenciaTratamiento.diasRestantes(t, ahora), isNull);
      expect(VigenciaTratamiento.textoParaPaciente(t, ahora), isNull);
    });

    test('fecha de fin es inclusiva y el primer día muestra el total', () {
      final t = _tratamiento(
        fechaInicio: DateTime(2026, 11, 2),
        duracionDias: 5,
      );

      expect(VigenciaTratamiento.fechaFin(t), DateTime(2026, 11, 6));
      expect(VigenciaTratamiento.diasRestantes(t, DateTime(2026, 11, 2, 8)), 5);
      expect(
        VigenciaTratamiento.textoParaPaciente(t, DateTime(2026, 11, 2, 8)),
        'Te quedan 5 días',
      );
    });

    test('último día: vigente, queda 1 y texto de último día', () {
      final t = _tratamiento(
        fechaInicio: DateTime(2026, 11, 2),
        duracionDias: 5,
      );
      final ultimoDia = DateTime(2026, 11, 6, 23, 59);

      expect(VigenciaTratamiento.estaVigente(t, ultimoDia), isTrue);
      expect(VigenciaTratamiento.diasRestantes(t, ultimoDia), 1);
      expect(
        VigenciaTratamiento.textoParaPaciente(t, ultimoDia),
        'Hoy es el último día',
      );
    });

    test('ya terminado: no vigente, 0 días y texto terminado', () {
      final t = _tratamiento(
        fechaInicio: DateTime(2026, 11, 2),
        duracionDias: 5,
      );
      final diaSiguiente = DateTime(2026, 11, 7);

      expect(VigenciaTratamiento.estaVigente(t, diaSiguiente), isFalse);
      expect(VigenciaTratamiento.diasRestantes(t, diaSiguiente), 0);
      expect(
        VigenciaTratamiento.textoParaPaciente(t, diaSiguiente),
        'Tratamiento terminado',
      );
    });

    test(
      'el cambio de día ocurre a medianoche, no por horas transcurridas',
      () {
        final t = _tratamiento(
          fechaInicio: DateTime(2026, 11, 2),
          duracionDias: 5,
        );

        expect(
          VigenciaTratamiento.estaVigente(t, DateTime(2026, 11, 6, 23, 59, 59)),
          isTrue,
        );
        expect(
          VigenciaTratamiento.estaVigente(t, DateTime(2026, 11, 7)),
          isFalse,
        );
        expect(
          VigenciaTratamiento.textoParaPaciente(
            t,
            DateTime(2026, 11, 6, 23, 59),
          ),
          'Hoy es el último día',
        );
        expect(
          VigenciaTratamiento.textoParaPaciente(t, DateTime(2026, 11, 7)),
          'Tratamiento terminado',
        );
      },
    );
  });
}
