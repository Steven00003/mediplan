import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/lista_pacientes.dart';
import 'package:mediplan/widgets/tarjeta_paciente.dart';

void main() {
  testWidgets('ListaPacientes construye 200 pacientes sin errores', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pacientes = List.generate(
      200,
      (i) => Paciente(
        id: 'p$i',
        nombre: 'Paciente con nombre largo $i',
        cuidadorId: 'c1',
        codigoVinculacion: 'MEDI-$i',
        dispositivoVinculadoId: i.isEven ? 'uid-$i' : '',
        edad: 60 + (i % 30),
        condicion: 'Condición crónica ${i % 5}',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: ListaPacientes(
            pacientes: pacientes,
            onTap: (_) {},
            footer: const SizedBox(
              key: ValueKey('footer'),
              height: 40,
              child: Text('Actividad reciente'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(TarjetaPaciente), findsWidgets);
    expect(find.byType(TarjetaPaciente).evaluate().length, lessThan(200));
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('footer')),
      500,
      maxScrolls: 100,
    );
    expect(find.text('Actividad reciente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
