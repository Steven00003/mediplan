// Pruebas puras de "Comprobar mi celular": qué puntos existen según Android,
// qué guía corresponde a cada fabricante y cómo se formatean los datos. No usan
// Flutter, canales nativos ni Firestore.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediplan/services/notificaciones_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mediplan/utils/comprobar_celular.dart';

void main() {
  group('puntosCelularParaSdk', () {
    test('Android 9 y 11 no muestran alarmas exactas ni pantalla completa', () {
      for (final sdk in [28, 30]) {
        expect(puntosCelularParaSdk(sdk), [
          PuntoCelular.notificaciones,
          PuntoCelular.bateria,
          PuntoCelular.detallesApp,
        ]);
      }
    });

    test('Android 12 añade alarmas exactas', () {
      expect(puntosCelularParaSdk(31), [
        PuntoCelular.notificaciones,
        PuntoCelular.alarmasExactas,
        PuntoCelular.bateria,
        PuntoCelular.detallesApp,
      ]);
    });

    test('Android 14 añade pantalla completa', () {
      expect(puntosCelularParaSdk(34), [
        PuntoCelular.notificaciones,
        PuntoCelular.alarmasExactas,
        PuntoCelular.pantallaCompleta,
        PuntoCelular.bateria,
        PuntoCelular.detallesApp,
      ]);
    });

    test('versiones anteriores a Android 6 no muestran optimización', () {
      expect(puntosCelularParaSdk(21), [
        PuntoCelular.notificaciones,
        PuntoCelular.detallesApp,
      ]);
    });

    test('sin versión solo muestra los puntos universales', () {
      expect(puntosCelularParaSdk(null), [
        PuntoCelular.notificaciones,
        PuntoCelular.detallesApp,
      ]);
    });
  });

  group('guiaParaFabricante', () {
    test('Huawei y Honor comparten la guía con el paso exacto', () {
      final huawei = guiaParaFabricante('HUAWEI');
      final honor = guiaParaFabricante('honor');

      expect(huawei.nombre, 'Huawei u Honor');
      expect(honor.nombre, huawei.nombre);
      expect(
        huawei.pasos,
        contains(
          'Inicio de aplicaciones: administrar manualmente y activar inicio '
          'automático, inicio secundario y ejecución en segundo plano.',
        ),
      );
    });

    test('reconoce Xiaomi, Redmi y POCO', () {
      for (final marca in ['Xiaomi', 'Redmi', 'POCO']) {
        expect(guiaParaFabricante(marca).nombre, 'Xiaomi, Redmi o POCO');
      }
    });

    test('reconoce Samsung, Oppo/Realme/Vivo y Motorola', () {
      expect(guiaParaFabricante('samsung').nombre, 'Samsung');
      for (final marca in ['OPPO', 'realme', 'vivo']) {
        expect(guiaParaFabricante(marca).nombre, 'Oppo, Realme o Vivo');
      }
      expect(guiaParaFabricante('motorola').nombre, 'Motorola');
      expect(guiaParaFabricante('Moto G20').nombre, 'Motorola');
    });

    test('una marca desconocida recibe pasos genéricos', () {
      expect(guiaParaFabricante('').nombre, 'Otros celulares');
      expect(guiaParaFabricante('marca rara').nombre, 'Otros celulares');
    });

    test('aclara que los menús pueden variar según el modelo', () {
      expect(
        notaGuiaFabricante,
        'Los nombres de los menús pueden variar según el modelo.',
      );
    });
  });

  group('faltanPermisosCriticos', () {
    test('Android 9 no cuenta alarmas exactas ni pantalla completa', () {
      expect(
        faltanPermisosCriticos(
          sdkInt: 28,
          notificaciones: true,
          alarmasExactas: false,
          pantallaCompleta: false,
          bateriaSinRestricciones: true,
        ),
        isFalse,
      );
    });

    test('Android 12 sí cuenta alarmas exactas', () {
      expect(
        faltanPermisosCriticos(
          sdkInt: 31,
          notificaciones: true,
          alarmasExactas: false,
          pantallaCompleta: null,
          bateriaSinRestricciones: true,
        ),
        isTrue,
      );
    });

    test('Android 14 sí cuenta pantalla completa', () {
      expect(
        faltanPermisosCriticos(
          sdkInt: 34,
          notificaciones: true,
          alarmasExactas: true,
          pantallaCompleta: false,
          bateriaSinRestricciones: true,
        ),
        isTrue,
      );
    });

    test('notificaciones y batería siempre cuentan', () {
      expect(
        faltanPermisosCriticos(
          sdkInt: 28,
          notificaciones: false,
          alarmasExactas: null,
          pantallaCompleta: null,
          bateriaSinRestricciones: true,
        ),
        isTrue,
      );
      expect(
        faltanPermisosCriticos(
          sdkInt: 28,
          notificaciones: true,
          alarmasExactas: null,
          pantallaCompleta: null,
          bateriaSinRestricciones: false,
        ),
        isTrue,
      );
    });

    test('un dato desconocido no dispara el aviso', () {
      expect(
        faltanPermisosCriticos(
          sdkInt: 34,
          notificaciones: null,
          alarmasExactas: null,
          pantallaCompleta: null,
          bateriaSinRestricciones: null,
        ),
        isFalse,
      );
    });
  });

  group('textos de la lista', () {
    test('clasifica los tres tipos de notificación', () {
      expect(etiquetaTipoAlarma('principal_puntual'), 'Alarma');
      expect(etiquetaTipoAlarma('posponer'), 'Alarma');
      expect(etiquetaTipoAlarma('aviso_previo'), 'Aviso previo');
      expect(etiquetaTipoAlarma('recordatorio_tardio'), 'Recordatorio');
      expect(etiquetaTipoAlarma('recordatorio_tardio_puntual'), 'Recordatorio');
      expect(etiquetaTipoAlarma('prueba'), 'Alarma de prueba');
    });

    test('muestra la hora local y distingue otro día', () {
      final ahora = DateTime(2026, 11, 21, 10, 0);
      expect(textoHoraLocal(DateTime(2026, 11, 21, 8, 5), ahora), '08:05');
      expect(
        textoHoraLocal(DateTime(2026, 11, 22, 8, 5), ahora),
        'Mañana 08:05',
      );
      expect(
        textoHoraLocal(DateTime(2026, 11, 25, 8, 5), ahora),
        '25/11 08:05',
      );
      expect(textoHoraLocal(null, ahora), 'Hora no disponible');
    });

    test('describe versión de Android y batería', () {
      expect(textoVersionAndroid(30, '11'), 'Android 11 (API 30)');
      expect(textoEstadoBateria(true), 'Batería sin restricciones');
      expect(textoEstadoBateria(false), 'Optimización de batería activa');
    });

    test('reconstruye una alarma desde su payload si falta el metadato', () {
      final ahora = DateTime(2026, 11, 21, 9, 0);
      expect(
        horaDesdePayloadAlarma('tratamiento1|10:30', ahora),
        DateTime(2026, 11, 21, 10, 30),
      );
      expect(
        horaDesdePayloadAlarma('tratamiento1|08:00', ahora),
        DateTime(2026, 11, 22, 8, 0),
      );
      expect(
        horaDesdePayloadAlarma('recordatorio|tratamiento1', ahora),
        isNull,
      );
    });
  });

  test('canal de alarma migrado a v2', () {
    expect(NotificacionesService.canalAlarmasId, 'alarmas_medicamentos_v2');
  });

  test('guia Huawei menciona alarma como notificacion', () {
    final guia = guiaParaFabricante('Huawei');
    expect(guia.pasos.join(' '), contains('llega como notificación'));
  });

  test('timeout de la notificacion de alarma es 15 minutos', () {
    expect(
      NotificacionesService.timeoutAlarmaNotificacionMs,
      15 * 60 * 1000,
    );
  });

  test('no muestra fila de canal en Android 7 o menor', () {
    expect(mostrarFilaCanalAlarmas(24), isFalse);
    expect(mostrarFilaCanalAlarmas(25), isFalse);
  });

  test('muestra fila de canal desde Android 8', () {
    expect(mostrarFilaCanalAlarmas(26), isTrue);
  });

  test('canal en problema si notificaciones desactivadas', () {
    final canal = AndroidNotificationChannel(
      'alarmas_medicamentos_v2',
      'Alarmas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    expect(
      canalAlarmasEnProblema(canal, notificacionesHabilitadas: false),
      isTrue,
    );
  });

  test('canal en problema si esta en silencio', () {
    final canal = AndroidNotificationChannel(
      'alarmas_medicamentos_v2',
      'Alarmas',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    expect(
      canalAlarmasEnProblema(canal, notificacionesHabilitadas: true),
      isTrue,
    );
  });

  test('canal listo no esta en problema', () {
    final canal = AndroidNotificationChannel(
      'alarmas_medicamentos_v2',
      'Alarmas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    expect(
      canalAlarmasEnProblema(canal, notificacionesHabilitadas: true),
      isFalse,
    );
  });
}
