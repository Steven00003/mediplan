import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/screens/doctor/detalle_paciente_screen.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/avatar_paciente.dart';
import 'package:mediplan/widgets/estados.dart';

Paciente _pacienteLargo() {
  return const Paciente(
    id: 'pac-largo',
    nombre: 'Adelina Adelina Rodríguez',
    cuidadorId: 'cuid-1',
    codigoVinculacion: 'MEDI-XXXXXX',
    dispositivoVinculadoId: 'uid-paciente',
    edad: 78,
    condicion: 'Ninguna condición crónica registrada',
    contactoEmergencia: '+57 300 123 4567',
  );
}

void main() {
  const tamanos = <Size>[
    Size(320, 568),
    Size(360, 640),
    Size(411, 891),
  ];
  const escalas = <double>[1.0, 1.3, 2.0];

  for (final tamano in tamanos) {
    for (final escala in escalas) {
      testWidgets(
        'FichaPaciente no solapa nombre, edad ni condición a ${tamano.width}x${tamano.height} escala $escala',
        (tester) async {
          tester.view.physicalSize = tamano;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: tamano,
                  textScaler: TextScaler.linear(escala),
                ),
                child: Scaffold(
                  body: FichaPaciente(paciente: _pacienteLargo()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Adelina Adelina Rodríguez'), findsOneWidget);
          expect(find.textContaining('Emergencia: +57 300 123 4567'), findsOneWidget);
          expect(find.byType(AvatarPaciente), findsOneWidget);

          final rectNombre = tester.getRect(
            find.text('Adelina Adelina Rodríguez'),
          );
          final rectEdad = tester.getRect(find.text('78 años'));
          final rectCondicion = tester.getRect(
            find.text('Ninguna condición crónica registrada'),
          );
          expect(rectNombre.overlaps(rectEdad), isFalse);
          expect(rectNombre.overlaps(rectCondicion), isFalse);
          expect(rectEdad.overlaps(rectCondicion), isFalse);
        },
      );
    }
  }

  for (final tamano in tamanos) {
    testWidgets(
      'SeccionVinculacion colapsada no desborda a ${tamano.width}x${tamano.height}',
      (tester) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(size: tamano),
              child: Scaffold(
                body: SeccionVinculacionDispositivo(
                  paciente: _pacienteLargo(),
                  vinculado: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Vinculación y dispositivo'), findsOneWidget);
        expect(find.text('Mostrar'), findsOneWidget);
        expect(find.text('MEDI-XXXXXX'), findsNothing);
      },
    );

    testWidgets(
      'SeccionVinculacion desplegada muestra el código completo a ${tamano.width}x${tamano.height}',
      (tester) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(size: tamano),
              child: Scaffold(
                body: SeccionVinculacionDispositivo(
                  paciente: _pacienteLargo(),
                  vinculado: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mostrar'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('MEDI-XXXXXX'), findsOneWidget);
        expect(find.text('Ocultar'), findsOneWidget);
      },
    );
  }

  testWidgets('EstadoVacio de medicamentos no desborda', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: EstadoVacio(
            icono: Icons.medication,
            titulo: 'Aún no hay medicamentos',
            mensaje: 'Agrega el primero con el botón de abajo.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Aún no hay medicamentos'), findsOneWidget);
  });
}
