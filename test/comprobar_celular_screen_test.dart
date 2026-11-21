import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/screens/paciente/comprobar_celular_screen.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/utils/comprobar_celular.dart';
import 'package:mediplan/widgets/lista_comprobacion_celular.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: child,
  );
}

EstadoCelular _estado() {
  return EstadoCelular(
    sdkInt: 34,
    fabricante: 'HUAWEI',
    versionAndroid: '14',
    notificacionesPermitidas: true,
    alarmasExactasPermitidas: false,
    pantallaCompletaPermitida: true,
    bateriaSinRestricciones: true,
    alarmas: [
      AlarmaEnCelular(
        tipo: 'principal_puntual',
        hora: DateTime(2026, 11, 21, 8),
      ),
      AlarmaEnCelular(
        tipo: 'aviso_previo',
        hora: DateTime(2026, 11, 22, 7, 55),
      ),
    ],
    ultimoRearme: DateTime(2026, 11, 21, 7, 30),
    ultimoErrorSincronizacion: 'Parece que no tienes conexión. Revisa tu internet e inténtalo de nuevo.',
  );
}

void main() {
  testWidgets('la lista muestra Listo/Pendiente y abre cada ajuste', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PuntoCelular? abierto;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ListaComprobacionCelular(
              puntos: const [
                PuntoComprobacionVista(
                  punto: PuntoCelular.notificaciones,
                  listo: true,
                ),
                PuntoComprobacionVista(
                  punto: PuntoCelular.alarmasExactas,
                  listo: false,
                ),
                PuntoComprobacionVista(
                  punto: PuntoCelular.bateria,
                  listo: true,
                ),
                PuntoComprobacionVista(
                  punto: PuntoCelular.detallesApp,
                  listo: true,
                ),
              ],
              onAbrir: (punto) => abierto = punto,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Listo'), findsNWidgets(3));
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Abrir notificaciones'), findsOneWidget);
    expect(find.text('Abrir alarmas exactas'), findsOneWidget);
    expect(find.text('Abrir batería'), findsOneWidget);
    expect(find.text('Abrir detalles'), findsOneWidget);

    await tester.tap(find.text('Abrir alarmas exactas'));
    await tester.pump();
    expect(abierto, PuntoCelular.alarmasExactas);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la pantalla completa no desborda a 320 dp con texto 1.3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(ComprobarCelularScreen(cargarEstado: () async => _estado())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comprobar mi celular'), findsOneWidget);
    expect(find.text('Revisemos tu celular'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // La lista es desplazable: al bajar aparecen la guía, la prueba y el error
    // de sincronización sin que el layout lance un overflow.
    await tester.scrollUntilVisible(
      find.textContaining('Huawei u Honor'),
      300,
    );
    expect(find.textContaining('Huawei u Honor'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Probar alarma en 60 s'), 300);
    expect(find.text('Probar alarma en 60 s'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Alarma'), 300);
    expect(find.text('Alarma'), findsOneWidget);
    expect(find.text('Aviso previo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Último error de sincronización'),
      300,
    );
    expect(find.text('Último rearmado'), findsOneWidget);
    expect(find.text('Último error de sincronización'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
