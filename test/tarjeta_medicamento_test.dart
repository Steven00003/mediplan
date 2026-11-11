import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/tarjeta_medicamento.dart';

Widget _app(Widget child) {
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
  testWidgets('TarjetaMedicamento muestra dosis, vigencia y chips por día', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: TarjetaMedicamento(
            ahora: DateTime(2026, 11, 11, 12),
            tratamiento: Tratamiento(
              id: 't1',
              pacienteId: 'p1',
              nombreMedicamento: 'Metformina de liberación prolongada 850 mg',
              dosis: '1 tableta',
              frecuencia: 'Diaria',
              fechaInicio: DateTime(2026, 11, 1),
              duracionDias: 30,
              horarios: const [
                HorarioDia(hora: '08:00', dias: [1, 2, 3, 4, 5]),
                HorarioDia(hora: '20:00', dias: [1, 2, 3, 4, 5]),
                HorarioDia(hora: '12:00', dias: [6, 7]),
              ],
            ),
            onTap: () {},
            onEliminar: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dosis: 1 tableta'), findsOneWidget);
    expect(find.text('Vigente'), findsOneWidget);
    expect(find.text('Quedan 20 días'), findsOneWidget);
    expect(find.text('Lun 08:00 · 20:00'), findsOneWidget);
    expect(find.text('Sáb 12:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
