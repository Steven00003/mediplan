import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/screens/doctor/editar_paciente_screen.dart';
import 'package:mediplan/theme/app_theme.dart';

const Paciente _paciente = Paciente(
  id: 'p1',
  nombre: 'José Antonio de la Cruz',
  cuidadorId: 'c1',
  codigoVinculacion: 'MEDI-ABC123',
  dispositivoVinculadoId: '',
  edad: 92,
  condicion:
      'Insuficiencia cardíaca congestiva con fibrilación auricular permanente',
  contactoEmergencia: '+34 600 000 000',
);

Widget _app(Widget home) {
  return MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: home,
  );
}

void _telefonoPequeno(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _HostEditar extends StatelessWidget {
  final Paciente paciente;

  const _HostEditar({required this.paciente});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditarPacienteScreen(paciente: paciente),
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('EditarPacienteScreen no desborda a 320 dp y textScale 1.3', (
    WidgetTester tester,
  ) async {
    _telefonoPequeno(tester);

    await tester.pumpWidget(
      _app(const EditarPacienteScreen(paciente: _paciente)),
    );
    await tester.pump();

    expect(find.text('Editar paciente'), findsOneWidget);
    expect(find.text('José Antonio de la Cruz'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);
    expect(find.text('Quitar foto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('salir con cambios pide confirmación y Cancelar no descarta', (
    WidgetTester tester,
  ) async {
    _telefonoPequeno(tester);

    await tester.pumpWidget(_app(const _HostEditar(paciente: _paciente)));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Nombre nuevo');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('¿Descartar cambios?'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Editar paciente'), findsOneWidget);
    expect(find.text('Nombre nuevo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
