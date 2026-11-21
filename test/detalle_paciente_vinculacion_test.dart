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

void main() {
  testWidgets('tarjeta vinculada compacta no desborda a 320 dp y textScale 1.3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: CardCodigoVinculacion(
            paciente: _paciente(vinculado: true),
            vinculado: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dispositivo vinculado'), findsOneWidget);
    expect(find.text('MEDI-ABCDEF'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarjeta no vinculada no desborda a 320 dp y textScale 1.3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: CardCodigoVinculacion(
            paciente: _paciente(vinculado: false),
            vinculado: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MEDI-ABCDEF'), findsOneWidget);
    expect(find.text('Generar código nuevo'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
