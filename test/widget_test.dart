// Pruebas de humo de la app. No requieren conexión con Firebase: verifican la
// selección de rol, el login y que ambas pantallas no desborden en móvil
// pequeño con texto ampliado.
//
// Estas pruebas no inician Firebase (requeriría el emulador y configuración),
// por lo que solo cubren widgets puros. Las pantallas que dependen de Firebase
// no se prueban unitariamente; se validan en el flujo manual end-to-end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mediplan/screens/doctor/login_screen.dart';
import 'package:mediplan/screens/seleccion_rol_screen.dart';
import 'package:mediplan/theme/app_theme.dart';

Future<void> _pumpSeleccionRol(
  WidgetTester tester, {
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SeleccionRolScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpLogin(WidgetTester tester, {double textScale = 1.0}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const LoginScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Sin vinculación se ven las dos tarjetas', (
    WidgetTester tester,
  ) async {
    await _pumpSeleccionRol(tester);

    expect(find.text('MediPlan'), findsOneWidget);
    expect(find.text('¿Quién es?'), findsOneWidget);
    expect(find.text('Paciente'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.textContaining('Entrar como'), findsNothing);
  });

  testWidgets('Con vinculación se ve el saludo, la tarjeta y el enlace', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ultima_vinculacion_paciente_id': 'paciente-1',
      'ultima_vinculacion_codigo': 'MEDI-ABC123',
      'ultima_vinculacion_nombre': 'Ana',
    });

    await _pumpSeleccionRol(tester);

    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Entrar como Ana'), findsOneWidget);
    expect(find.text('Sin escribir código'), findsOneWidget);
    expect(find.text('¿No eres Ana? Usar otro código'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Paciente'), findsNothing);
  });

  testWidgets('Usar otro código pide confirmación y Cancelar no borra nada', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ultima_vinculacion_paciente_id': 'paciente-1',
      'ultima_vinculacion_codigo': 'MEDI-ABC123',
      'ultima_vinculacion_nombre': 'Ana',
    });

    await _pumpSeleccionRol(tester);
    await tester.tap(find.text('¿No eres Ana? Usar otro código'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Este celular olvidará a Ana'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ultima_vinculacion_paciente_id'), 'paciente-1');
    expect(find.text('Entrar como Ana'), findsOneWidget);
  });

  testWidgets('Sin nombre local se ofrece Continuar como paciente', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ultima_vinculacion_paciente_id': 'paciente-1',
    });

    await _pumpSeleccionRol(tester);

    expect(find.text('Hola'), findsOneWidget);
    expect(find.text('Continuar como paciente'), findsOneWidget);
    expect(find.text('¿No eres tú? Usar otro código'), findsOneWidget);
  });

  testWidgets(
    'Con vinculación no desborda a textScale 1.3 en pantalla pequeña',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'ultima_vinculacion_paciente_id': 'paciente-1',
        'ultima_vinculacion_codigo': 'MEDI-ABC123',
        'ultima_vinculacion_nombre': 'Ana',
      });

      await _pumpSeleccionRol(tester, textScale: 1.3);

      expect(find.text('Entrar como Ana'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Selección de rol sin vinculación no desborda a 320 dp y textScale 1.3',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSeleccionRol(tester, textScale: 1.3);

      expect(find.text('Paciente'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Login no desborda a 320 dp y textScale 1.3', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpLogin(tester, textScale: 1.3);

    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('formato de código de vinculación', () {
    // El código generado debería respetar el formato MEDI-XXXXXX.
    final regex = RegExp(r'^MEDI-[A-HJ-NP-Z2-9]{6}$');
    expect(regex.hasMatch('MEDI-K4T7Q2'), isTrue);
    expect(regex.hasMatch('MEDI-OOO111'), isFalse); // caracteres ambiguos
  });
}
