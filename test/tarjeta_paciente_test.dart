import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/tarjeta_paciente.dart';

const String _fotoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=';

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

void _telefonoPequeno(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('TarjetaPaciente muestra inicial, edad, condición y vínculo', (
    WidgetTester tester,
  ) async {
    _telefonoPequeno(tester);

    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: TarjetaPaciente(
            paciente: const Paciente(
              id: 'p1',
              nombre: 'María Fernanda',
              cuidadorId: 'c1',
              codigoVinculacion: 'MEDI-ABC123',
              dispositivoVinculadoId: 'uid-paciente',
              edad: 78,
              condicion: 'Hipertensión y diabetes tipo 2',
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('María Fernanda'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('78 años'), findsOneWidget);
    expect(find.text('Hipertensión y diabetes tipo 2'), findsOneWidget);
    expect(find.text('Vinculado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TarjetaPaciente usa la foto si existe', (
    WidgetTester tester,
  ) async {
    _telefonoPequeno(tester);

    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: TarjetaPaciente(
            paciente: const Paciente(
              id: 'p2',
              nombre: 'Carlos',
              cuidadorId: 'c1',
              codigoVinculacion: 'MEDI-XYZ789',
              dispositivoVinculadoId: 'uid-paciente',
              edad: 64,
              fotoBase64: _fotoBase64,
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isNotNull);
    expect(find.text('C'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TarjetaPaciente muestra Sin vincular sin desbordar a 320 dp', (
    WidgetTester tester,
  ) async {
    _telefonoPequeno(tester);

    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: TarjetaPaciente(
            paciente: const Paciente(
              id: 'p3',
              nombre: 'José Antonio de la Cruz',
              cuidadorId: 'c1',
              codigoVinculacion: 'MEDI-LARGO1',
              dispositivoVinculadoId: '',
              edad: 92,
              condicion: 'Insuficiencia cardíaca congestiva con fibrilación auricular permanente',
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sin vincular'), findsOneWidget);
    expect(find.text('J'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
