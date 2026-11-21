import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mediplan/services/conexion_service.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/banner_sin_conexion.dart';

const String _mensaje =
    'Sin conexión. Puede que estés viendo datos desactualizados.';

Widget _app(ConexionService servicio, {double textScale = 1.0}) {
  return ChangeNotifierProvider<ConexionService>.value(
    value: servicio,
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: BannerSinConexion(mensaje: _mensaje)),
    ),
  );
}

void main() {
  // `tester.pump` usa el reloj fake async del binding de pruebas, así que estos
  // casos ejercitan el debounce real de ConexionService sin esperar 4 s.
  testWidgets('el aviso aparece tras 4 s de caché', (tester) async {
    final servicio = ConexionService();
    addTearDown(servicio.dispose);
    await tester.pumpWidget(_app(servicio));

    expect(find.text(_mensaje), findsNothing);

    servicio.reportar(true);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(_mensaje), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(_mensaje), findsOneWidget);
  });

  testWidgets('no aparece si vuelve la conexión antes de 4 s', (tester) async {
    final servicio = ConexionService();
    addTearDown(servicio.dispose);
    await tester.pumpWidget(_app(servicio));

    servicio.reportar(true);
    await tester.pump(const Duration(seconds: 3));
    servicio.reportar(false);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text(_mensaje), findsNothing);
  });

  testWidgets('desaparece sola al volver la conexión', (tester) async {
    final servicio = ConexionService();
    addTearDown(servicio.dispose);
    await tester.pumpWidget(_app(servicio));

    servicio.reportar(true);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(_mensaje), findsOneWidget);

    servicio.reportar(false);
    await tester.pumpAndSettle();
    expect(find.text(_mensaje), findsNothing);
  });

  testWidgets('el banner no desborda a 320 dp y textScale 1.3', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final servicio = ConexionService();
    addTearDown(servicio.dispose);
    await tester.pumpWidget(_app(servicio, textScale: 1.3));

    servicio.reportar(true);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text(_mensaje), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
