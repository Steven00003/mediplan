import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/paciente.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/widgets/avatar_paciente.dart';

const String _fotoValida =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=';

Widget _app(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

Paciente _paciente({String? fotoBase64}) {
  return Paciente(
    id: 'p1',
    nombre: 'María',
    cuidadorId: 'c1',
    codigoVinculacion: 'MEDI-ABC123',
    fotoBase64: fotoBase64,
  );
}

void main() {
  testWidgets('AvatarPaciente decodifica una sola vez con la misma foto', (
    WidgetTester tester,
  ) async {
    var llamadas = 0;
    final bytes = base64Decode(_fotoValida);
    Uint8List? decodificador(String foto) {
      llamadas++;
      return bytes;
    }

    final paciente = _paciente(fotoBase64: 'foto-a');
    await tester.pumpWidget(
      _app(AvatarPaciente(paciente: paciente, decodificador: decodificador)),
    );
    expect(llamadas, 1);

    await tester.pumpWidget(
      _app(AvatarPaciente(paciente: paciente, decodificador: decodificador)),
    );
    expect(llamadas, 1);
  });

  testWidgets('AvatarPaciente vuelve a decodificar si cambia la foto', (
    WidgetTester tester,
  ) async {
    var llamadas = 0;
    final bytes = base64Decode(_fotoValida);
    Uint8List? decodificador(String foto) {
      llamadas++;
      return bytes;
    }

    await tester.pumpWidget(
      _app(
        AvatarPaciente(
          paciente: _paciente(fotoBase64: 'foto-a'),
          decodificador: decodificador,
        ),
      ),
    );
    expect(llamadas, 1);

    await tester.pumpWidget(
      _app(
        AvatarPaciente(
          paciente: _paciente(fotoBase64: 'foto-b'),
          decodificador: decodificador,
        ),
      ),
    );
    expect(llamadas, 2);
  });

  testWidgets(
    'AvatarPaciente muestra la inicial sin foto o con foto inválida',
    (WidgetTester tester) async {
      await tester.pumpWidget(_app(AvatarPaciente(paciente: _paciente())));
      expect(find.text('M'), findsOneWidget);

      await tester.pumpWidget(
        _app(
          AvatarPaciente(paciente: _paciente(fotoBase64: 'esto-no-es-base64')),
        ),
      );
      expect(find.text('M'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
