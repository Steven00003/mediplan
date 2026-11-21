// Pruebas puras del reporte del celular del paciente: throttle de escritura,
// lectura del mapa anidado y cálculo del aviso que ve el cuidador. No requieren
// Firebase, Firestore ni SharedPreferences.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/models/estado_dispositivo.dart';
import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/utils/reporte_estado_dispositivo.dart';

EstadoDispositivo estado({
  DateTime? ultima,
  int alarmas = 12,
  bool notificaciones = true,
  bool bateria = true,
}) {
  return EstadoDispositivo(
    ultimaSincronizacion: ultima,
    alarmasProgramadas: alarmas,
    notificacionesPermitidas: notificaciones,
    bateriaSinRestricciones: bateria,
    versionAndroid: 35,
    fabricante: 'samsung',
    versionApp: '1.0.0+1',
  );
}

void main() {
  final ahora = DateTime(2026, 11, 20, 12);

  group('debeReportarEstadoDispositivo', () {
    test('reporta la primera vez', () {
      expect(
        debeReportarEstadoDispositivo(
          ahora: ahora,
          ultimoEnvio: null,
          firmaAnterior: null,
          firmaActual: 'p1|12',
        ),
        isTrue,
      );
    });

    test('no reescribe antes de 30 min si no cambió nada', () {
      expect(
        debeReportarEstadoDispositivo(
          ahora: ahora,
          ultimoEnvio: ahora.subtract(const Duration(minutes: 29)),
          firmaAnterior: 'p1|12',
          firmaActual: 'p1|12',
        ),
        isFalse,
      );
    });

    test('reescribe al cumplirse los 30 min', () {
      expect(
        debeReportarEstadoDispositivo(
          ahora: ahora,
          ultimoEnvio: ahora.subtract(const Duration(minutes: 30)),
          firmaAnterior: 'p1|12',
          firmaActual: 'p1|12',
        ),
        isTrue,
      );
    });

    test('un valor distinto se reporta de inmediato', () {
      expect(
        debeReportarEstadoDispositivo(
          ahora: ahora,
          ultimoEnvio: ahora.subtract(const Duration(minutes: 1)),
          firmaAnterior: 'p1|12',
          firmaActual: 'p1|11',
        ),
        isTrue,
      );
    });
  });

  group('necesitaAvisoAlarmas', () {
    test('avisa si no hay ningún reporte', () {
      expect(necesitaAvisoAlarmas(null, ahora), isTrue);
    });

    test('avisa si la última conexión supera 24 h', () {
      expect(
        necesitaAvisoAlarmas(
          estado(ultima: ahora.subtract(const Duration(hours: 25))),
          ahora,
        ),
        isTrue,
      );
    });

    test('no avisa exactamente a las 24 h si todo está bien', () {
      expect(
        necesitaAvisoAlarmas(
          estado(ultima: ahora.subtract(const Duration(hours: 24))),
          ahora,
        ),
        isFalse,
      );
    });

    test('avisa si faltan permisos de notificaciones', () {
      expect(
        necesitaAvisoAlarmas(
          estado(ultima: ahora, notificaciones: false),
          ahora,
        ),
        isTrue,
      );
    });

    test('avisa si la batería está restringida', () {
      expect(
        necesitaAvisoAlarmas(estado(ultima: ahora, bateria: false), ahora),
        isTrue,
      );
    });

    test('usa el texto exacto acordado', () {
      expect(
        mensajeAlarmasNoSuenan,
        'Es posible que las alarmas no suenen. Pide al paciente que abra MediPlan.',
      );
    });
  });

  group('textoUltimaSincronizacion', () {
    test('muestra minutos y horas en formato compacto', () {
      expect(
        textoUltimaSincronizacion(
          ahora.subtract(const Duration(minutes: 5)),
          ahora,
        ),
        'hace 5 min',
      );
      expect(
        textoUltimaSincronizacion(
          ahora.subtract(const Duration(hours: 2)),
          ahora,
        ),
        'hace 2 horas',
      );
      expect(textoUltimaSincronizacion(null, ahora), 'sin datos');
    });
  });

  group('EstadoDispositivo.fromValor', () {
    test('lee el mapa anidado y recorta campos largos', () {
      final leido = EstadoDispositivo.fromValor({
        'ultimaSincronizacion': ahora,
        'alarmasProgramadas': 21,
        'notificacionesPermitidas': true,
        'bateriaSinRestricciones': false,
        'versionAndroid': 34,
        'fabricante': 'x' * 60,
        'versionApp': '1.0.0+1',
      });

      expect(leido, isNotNull);
      expect(leido!.ultimaSincronizacion, ahora);
      expect(leido.alarmasProgramadas, 21);
      expect(leido.bateriaSinRestricciones, isFalse);
      expect(leido.fabricante.length, EstadoDispositivo.maxLargoFabricante);
    });

    test('Paciente.fromMap conserva el estado del dispositivo', () {
      final paciente = Paciente.fromMap('p1', {
        'nombre': 'Ana',
        'cuidadorId': 'c1',
        'codigoVinculacion': 'MEDI-AAAAAA',
        'dispositivoVinculadoId': 'uid-paciente',
        'estadoDispositivo': {
          'ultimaSincronizacion': ahora,
          'alarmasProgramadas': 3,
          'notificacionesPermitidas': true,
          'bateriaSinRestricciones': true,
          'versionAndroid': 35,
          'fabricante': 'Samsung',
          'versionApp': '1.0.0+1',
        },
      });

      expect(paciente.estadoDispositivo?.alarmasProgramadas, 3);
      expect(paciente.estadoDispositivo?.fabricante, 'Samsung');
      // No se debe reescribir desde una edición del cuidador.
      expect(paciente.toMap().containsKey('estadoDispositivo'), isFalse);
    });
  });
}
