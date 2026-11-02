import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/utils/reingreso_paciente.dart';

void main() {
  group('debeOfrecerContinuarComoPaciente', () {
    const recordada = VinculacionRecordada(
      pacienteId: 'pac-1',
      codigo: 'MEDI-K4T7Q2',
      nombre: 'María',
    );

    test('sin vinculación recordada no ofrece continuar', () {
      expect(
        debeOfrecerContinuarComoPaciente(
          recordada: null,
          pacienteActivo: false,
          sesionCuidador: false,
        ),
        isFalse,
      );
    });

    test('con vinculación válida y sin paciente activo sí ofrece', () {
      expect(
        debeOfrecerContinuarComoPaciente(
          recordada: recordada,
          pacienteActivo: false,
          sesionCuidador: false,
        ),
        isTrue,
      );
    });

    test('con paciente activo no ofrece continuar', () {
      expect(
        debeOfrecerContinuarComoPaciente(
          recordada: recordada,
          pacienteActivo: true,
          sesionCuidador: false,
        ),
        isFalse,
      );
    });

    test('con sesión de cuidador no ofrece continuar como paciente', () {
      expect(
        debeOfrecerContinuarComoPaciente(
          recordada: recordada,
          pacienteActivo: false,
          sesionCuidador: true,
        ),
        isFalse,
      );
    });

    test('una recordada sin pacienteId no cuenta como vinculación', () {
      const invalida = VinculacionRecordada(
        pacienteId: '   ',
        codigo: 'MEDI-K4T7Q2',
        nombre: 'María',
      );

      expect(invalida.esValida, isFalse);
      expect(
        debeOfrecerContinuarComoPaciente(
          recordada: invalida,
          pacienteActivo: false,
          sesionCuidador: false,
        ),
        isFalse,
      );
    });

    test('el código o el nombre vacíos no invalidan el reingreso', () {
      const sinCodigo = VinculacionRecordada(
        pacienteId: 'pac-1',
        codigo: '',
        nombre: '',
      );

      expect(sinCodigo.esValida, isTrue);
      expect(
        debeOfrecerContinuarComoPaciente(
          recordada: sinCodigo,
          pacienteActivo: false,
          sesionCuidador: false,
        ),
        isTrue,
      );
    });
  });
}
