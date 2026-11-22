import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/screens/doctor/detalle_paciente_screen.dart';
import 'package:mediplan/theme/app_theme.dart';

Paciente _paciente({required bool vinculado}) {
  return Paciente(
    id: 'pac-1',
    nombre: 'Ana',
    cuidadorId: 'cuid-1',
    codigoVinculacion: 'MEDI-ABCDEF',
    dispositivoVinculadoId: vinculado ? 'uid-paciente' : '',
  );
}

Widget _envolver(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('sección vinculada colapsada no desborda a 320 dp y 1.3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _envolver(
        SeccionVinculacionDispositivo(
          paciente: _paciente(vinculado: true),
          vinculado: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vinculación y dispositivo'), findsOneWidget);
    expect(find.text('Vinculado · última conexión sin datos'), findsOneWidget);
    expect(find.text('Mostrar'), findsOneWidget);
    expect(find.text('MEDI-ABCDEF'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sección sin vincular colapsada no desborda a 320 dp y 1.3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _envolver(
        SeccionVinculacionDispositivo(
          paciente: _paciente(vinculado: false),
          vinculado: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin vincular'), findsOneWidget);
    expect(find.text('MEDI-ABCDEF'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mostrar y Ocultar alternan el contenido de la sección', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _envolver(
        SeccionVinculacionDispositivo(
          paciente: _paciente(vinculado: false),
          vinculado: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();

    expect(find.text('Ocultar'), findsOneWidget);
    expect(find.text('MEDI-ABCDEF'), findsOneWidget);
    expect(find.text('Generar código nuevo'), findsOneWidget);

    await tester.tap(find.text('Ocultar'));
    await tester.pumpAndSettle();

    expect(find.text('Mostrar'), findsOneWidget);
    expect(find.text('MEDI-ABCDEF'), findsNothing);
  });

  testWidgets(
    'la sección vinculada expandida incluye el celular y desvincular',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _envolver(
          SeccionVinculacionDispositivo(
            paciente: _paciente(vinculado: true),
            vinculado: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mostrar'));
      await tester.pumpAndSettle();

      expect(find.text('Celular del paciente'), findsOneWidget);
      expect(find.text('Desvincular dispositivo'), findsOneWidget);
      expect(find.text('Generar código nuevo'), findsNothing);
    },
  );
}
