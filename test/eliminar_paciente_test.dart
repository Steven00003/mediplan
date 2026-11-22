import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mediplan/models/estado_dispositivo.dart';
import 'package:mediplan/theme/app_theme.dart';
import 'package:mediplan/utils/confirmacion_eliminar_paciente.dart';
import 'package:mediplan/utils/eliminacion_paciente.dart';
import 'package:mediplan/utils/limpieza_paciente.dart';
import 'package:mediplan/utils/lotes.dart';
import 'package:mediplan/utils/resumen_vinculacion.dart';
import 'package:mediplan/widgets/dialogo_eliminar_paciente.dart';

void main() {
  group('nombreConfirmaEliminacion', () {
    test('exige el nombre exacto, ignorando solo espacios exteriores', () {
      expect(
        nombreConfirmaEliminacion(
          nombrePaciente: 'Ana María',
          textoEscrito: '  Ana María ',
        ),
        isTrue,
      );
      expect(
        nombreConfirmaEliminacion(
          nombrePaciente: 'Ana María',
          textoEscrito: 'ana maría',
        ),
        isFalse,
      );
      expect(
        nombreConfirmaEliminacion(
          nombrePaciente: 'Ana María',
          textoEscrito: 'Ana',
        ),
        isFalse,
      );
      expect(
        nombreConfirmaEliminacion(nombrePaciente: '  ', textoEscrito: '  '),
        isFalse,
      );
    });
  });

  group('partirEnLotes', () {
    test('reparte en lotes de máximo 400 sin perder elementos', () {
      final elementos = List<int>.generate(801, (i) => i);
      final lotes = partirEnLotes(elementos, 400);
      expect(lotes.map((l) => l.length).toList(), [400, 400, 1]);
      expect(lotes.expand((l) => l).toList(), elementos);
    });

    test('un lote incompleto no se rellena', () {
      expect(partirEnLotes([1, 2, 3], 2).map((l) => l.length).toList(), [2, 1]);
    });

    test('lista vacía no produce lotes', () {
      expect(partirEnLotes<int>([], 400), isEmpty);
    });

    test('rechaza un tamaño inválido', () {
      expect(() => partirEnLotes([1], 0), throwsArgumentError);
    });
  });

  group('debeOlvidarPacientePorLectura', () {
    test('olvida si el documento no existe', () {
      expect(
        debeOlvidarPacientePorLectura(
          existePaciente: false,
          permisoDenegado: false,
        ),
        isTrue,
      );
    });

    test('olvida si la lectura fue rechazada por permisos', () {
      expect(
        debeOlvidarPacientePorLectura(
          existePaciente: true,
          permisoDenegado: true,
        ),
        isTrue,
      );
    });

    test('no olvida si el documento existe y solo falló la red', () {
      expect(
        debeOlvidarPacientePorLectura(
          existePaciente: true,
          permisoDenegado: false,
        ),
        isFalse,
      );
    });
  });

  group('resumenVinculacion', () {
    final ahora = DateTime(2026, 11, 22, 12);

    EstadoDispositivo estado({
      DateTime? ultima,
      bool notificaciones = true,
      bool bateria = true,
    }) {
      return EstadoDispositivo(
        ultimaSincronizacion: ultima,
        alarmasProgramadas: 3,
        notificacionesPermitidas: notificaciones,
        bateriaSinRestricciones: bateria,
        versionAndroid: 11,
        fabricante: 'Motorola',
        versionApp: '1.0.0',
      );
    }

    test(
      'vinculado muestra la última conexión y no advierte si todo está bien',
      () {
        final resumen = resumenVinculacion(
          vinculado: true,
          expiraCodigo: null,
          ahora: ahora,
          estadoDispositivo: estado(
            ultima: ahora.subtract(const Duration(hours: 2)),
          ),
        );
        expect(resumen.texto, 'Vinculado · última conexión hace 2 horas');
        expect(resumen.advertencia, isFalse);
      },
    );

    test('vinculado advierte si faltan permisos o pasaron más de 24 horas', () {
      final sinPermisos = resumenVinculacion(
        vinculado: true,
        expiraCodigo: null,
        ahora: ahora,
        estadoDispositivo: estado(
          ultima: ahora.subtract(const Duration(minutes: 5)),
          notificaciones: false,
        ),
      );
      expect(sinPermisos.advertencia, isTrue);

      final viejo = resumenVinculacion(
        vinculado: true,
        expiraCodigo: null,
        ahora: ahora,
        estadoDispositivo: estado(
          ultima: ahora.subtract(const Duration(days: 2)),
        ),
      );
      expect(viejo.advertencia, isTrue);
    });

    test('sin vincular distingue código vencido de código vigente', () {
      final vencido = resumenVinculacion(
        vinculado: false,
        expiraCodigo: ahora.subtract(const Duration(minutes: 1)),
        ahora: ahora,
        estadoDispositivo: null,
      );
      expect(vencido.texto, 'Código vencido');
      expect(vencido.advertencia, isFalse);

      final vigente = resumenVinculacion(
        vinculado: false,
        expiraCodigo: ahora.add(const Duration(hours: 1)),
        ahora: ahora,
        estadoDispositivo: null,
      );
      expect(vigente.texto, 'Sin vincular');
    });
  });

  group('ordenEliminacionPaciente', () {
    test('notifica solo después de borrar el paciente', () {
      final pasos = ordenEliminacionPaciente(
        tieneVinculo: true,
        notificarPaciente: true,
      );
      expect(pasos, <PasoEliminacionPaciente>[
        PasoEliminacionPaciente.tratamientos,
        PasoEliminacionPaciente.registrosToma,
        PasoEliminacionPaciente.vinculo,
        PasoEliminacionPaciente.paciente,
        PasoEliminacionPaciente.notificarPaciente,
      ]);
      expect(
        pasos.indexOf(PasoEliminacionPaciente.notificarPaciente),
        greaterThan(pasos.indexOf(PasoEliminacionPaciente.paciente)),
      );
    });

    test('sin código no intenta borrar vínculo', () {
      final pasos = ordenEliminacionPaciente(
        tieneVinculo: false,
        notificarPaciente: true,
      );
      expect(pasos.contains(PasoEliminacionPaciente.vinculo), isFalse);
      expect(pasos.last, PasoEliminacionPaciente.notificarPaciente);
    });

    test('sin token no notifica', () {
      final pasos = ordenEliminacionPaciente(
        tieneVinculo: true,
        notificarPaciente: false,
      );
      expect(
        pasos.contains(PasoEliminacionPaciente.notificarPaciente),
        isFalse,
      );
      expect(pasos.last, PasoEliminacionPaciente.paciente);
    });
  });

  testWidgets(
    'el botón de eliminar sigue deshabilitado hasta el nombre exacto',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: DialogoEliminarPaciente(nombrePaciente: 'Ana María'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      ElevatedButton boton() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Eliminar paciente'),
      );

      expect(boton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ana maría');
      await tester.pump();
      expect(boton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Ana María');
      await tester.pump();
      expect(boton().onPressed, isNotNull);
    },
  );
}
