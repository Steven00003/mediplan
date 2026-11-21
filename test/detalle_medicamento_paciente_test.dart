import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/tratamiento.dart';
import 'package:mediplan/screens/paciente/medicamentos_proximos_screen.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/utils/ventana_confirmacion.dart';

Tratamiento _tratamiento() {
  return Tratamiento(
    id: 'trat-1',
    pacienteId: 'pac-1',
    nombreMedicamento: 'Paracetamol',
    dosis: '1',
    frecuencia: 'Cada 8 horas',
    horarios: const [
      HorarioDia(hora: '08:00', dias: [1, 2, 3, 4, 5, 6, 7]),
    ],
  );
}

void main() {
  group('estaEnVentanaConfirmacion', () {
    final ahora = DateTime(2026, 11, 21, 10, 0);

    test('acepta desde 5 minutos antes hasta 2 minutos después', () {
      expect(
        estaEnVentanaConfirmacion(
          ahora.subtract(const Duration(minutes: 5)),
          ahora,
        ),
        isTrue,
      );
      expect(
        estaEnVentanaConfirmacion(ahora.add(const Duration(minutes: 2)), ahora),
        isTrue,
      );
    });

    test('rechaza fuera de la ventana', () {
      expect(
        estaEnVentanaConfirmacion(
          ahora.subtract(const Duration(minutes: 5, seconds: 1)),
          ahora,
        ),
        isFalse,
      );
      expect(
        estaEnVentanaConfirmacion(
          ahora.add(const Duration(minutes: 2, seconds: 1)),
          ahora,
        ),
        isFalse,
      );
    });
  });

  testWidgets('tocar un medicamento pide el detalle, no la alarma', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var abrioDetalle = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: TarjetaMedicamentoPaciente(
            tratamiento: _tratamiento(),
            registros: const [],
            onVerDetalle: () => abrioDetalle = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paracetamol'));
    await tester.pump();

    expect(abrioDetalle, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la tarjeta del medicamento no desborda a 320 dp y textScale 1.3',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: TarjetaMedicamentoPaciente(
              tratamiento: _tratamiento(),
              registros: const [],
              onVerDetalle: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaMedicamentoPaciente), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
