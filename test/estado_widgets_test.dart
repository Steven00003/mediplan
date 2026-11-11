import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/estados.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('EstadoVacio muestra su contenido y dispara la acción', (
    WidgetTester tester,
  ) async {
    var pulsado = false;

    await tester.pumpWidget(
      _app(
        EstadoVacio(
          icono: Icons.group_off,
          titulo: 'Aún no tienes pacientes',
          mensaje: 'Agrega uno para empezar.',
          accion: ElevatedButton(
            onPressed: () => pulsado = true,
            child: const Text('Agregar paciente'),
          ),
        ),
      ),
    );

    expect(find.text('Aún no tienes pacientes'), findsOneWidget);
    expect(find.text('Agrega uno para empezar.'), findsOneWidget);
    expect(find.text('Agregar paciente'), findsOneWidget);

    await tester.tap(find.text('Agregar paciente'));
    expect(pulsado, isTrue);
  });

  testWidgets('EstadoError muestra el mensaje amable y reintenta', (
    WidgetTester tester,
  ) async {
    var reintentos = 0;

    await tester.pumpWidget(
      _app(
        EstadoError(
          mensaje: 'No tienes conexión. Revisa tu internet.',
          onReintentar: () => reintentos++,
        ),
      ),
    );

    expect(find.text('No pudimos cargar esto'), findsOneWidget);
    expect(
      find.text('No tienes conexión. Revisa tu internet.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    expect(reintentos, 1);
  });

  testWidgets('EstadoCargando muestra el indicador y el texto', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(const EstadoCargando(texto: 'Cargando pacientes...')),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Cargando pacientes...'), findsOneWidget);
  });
}
