import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/acerca_de.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('Acerca de muestra nombre, versión, crédito y aviso médico', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => mostrarAcercaDe(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    final anio = DateTime.now().year;
    expect(find.text('Acerca de MediPlan'), findsOneWidget);
    expect(find.text('MediPlan'), findsOneWidget);
    expect(find.text('Versión 1.0.0+1'), findsOneWidget);
    expect(find.text('Proyecto académico UTS · © $anio'), findsOneWidget);
    expect(
      find.text(
        'MediPlan no es un dispositivo médico y no reemplaza la indicación de un médico.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Acerca de MediPlan'), findsNothing);
  });
}
