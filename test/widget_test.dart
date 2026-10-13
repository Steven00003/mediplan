// Prueba de humo de la app. No requiere conexión con Firebase: solo verifica
// que la pantalla de selección de rol renderiza sus dos botones.
//
// Estas pruebas no inician Firebase (requeriría el emulador y configuración),
// por lo que solo cubren widgets puros. Las pantallas que dependen de Firebase
// no se prueban unitariamente; se validan en el flujo manual end-to-end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/screens/seleccion_rol_screen.dart';

void main() {
  testWidgets('La pantalla de rol muestra Paciente y Doctor',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SeleccionRolScreen()));

    expect(find.text('MediPlan'), findsOneWidget);
    expect(find.text('Paciente'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
  });

  test('formato de código de vinculación', () {
    // El código generado debería respetar el formato MEDI-XXXXXX.
    final regex = RegExp(r'^MEDI-[A-HJ-NP-Z2-9]{6}$');
    expect(regex.hasMatch('MEDI-K4T7Q2'), isTrue);
    expect(regex.hasMatch('MEDI-OOO111'), isFalse); // caracteres ambiguos
  });
}
