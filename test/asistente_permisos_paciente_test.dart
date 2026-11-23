import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/screens/paciente/asistente_permisos_paciente_screen.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/utils/pasos_permisos_paciente.dart';

void main() {
  group('pasosAplicables', () {
    test('Android 10 muestra notificaciones, bateria e inicio automatico', () {
      expect(
        pasosAplicables(29),
        <PasoPermisoPaciente>[
          PasoPermisoPaciente.notificaciones,
          PasoPermisoPaciente.canalAlarmas,
          PasoPermisoPaciente.bateria,
          PasoPermisoPaciente.inicioAutomatico,
        ],
      );
    });

    test('Android 15 muestra todos los pasos', () {
      expect(
        pasosAplicables(35),
        PasoPermisoPaciente.values,
      );
    });

    test('Android 8 omite alarmas exactas y pantalla completa', () {
      final pasos = pasosAplicables(26);
      expect(pasos.contains(PasoPermisoPaciente.alarmasExactas), isFalse);
      expect(pasos.contains(PasoPermisoPaciente.pantallaCompleta), isFalse);
      expect(pasos.contains(PasoPermisoPaciente.canalAlarmas), isTrue);
    });
  });

  group('estadoDePaso y resumenPasos', () {
    test('un paso no aplicable es noAplica', () {
      expect(
        estadoDePaso(PasoPermisoPaciente.pantallaCompleta, 30, true),
        EstadoPasoPermiso.noAplica,
      );
    });

    test('resumen cuenta solo los aplicables', () {
      final resumen = resumenPasos(<EstadoPasoPermiso>[
        EstadoPasoPermiso.concedido,
        EstadoPasoPermiso.noAplica,
        EstadoPasoPermiso.pendiente,
      ]);
      expect(resumen.listos, 1);
      expect(resumen.pendientes, 1);
      expect(resumen.total, 2);
      expect(resumen.todoListo, isFalse);
    });

    test('resumen todoListo cuando no hay pendientes', () {
      final resumen = resumenPasos(<EstadoPasoPermiso>[
        EstadoPasoPermiso.concedido,
        EstadoPasoPermiso.concedido,
      ]);
      expect(resumen.todoListo, isTrue);
    });
  });

  testWidgets('asistente no desborda a 320 dp y textScale 1.3', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: AsistentePermisosPacienteScreen(
            sdkInt: 34,
            solicitar: (paso) async => true,
            comprobar: (paso) async => true,
            abrirAjustes: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
