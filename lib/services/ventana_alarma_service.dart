import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controla desde Dart los flags nativos de la ventana que usa la alarma.
///
/// La activación ocurre en `MainActivity` en cuanto detecta un intent de
/// notificación de alarma (`SELECT_NOTIFICATION` con payload), antes de que
/// Flutter pinte la pantalla. Este servicio solo desactiva esos flags cuando la
/// alarma se cierra o cuando el payload resulta inválido.
///
/// Los errores se ignoran a propósito: fuera de Android (tests o escritorio) el
/// canal no existe y eso no puede romper el flujo de la alarma.
class VentanaAlarmaService {
  const VentanaAlarmaService();

  static const MethodChannel _canal =
      MethodChannel('com.mediplan.mediplan/ventana_alarma');

  /// Quita `showWhenLocked`, `turnScreenOn` y `keepScreenOn` de la ventana.
  Future<void> desactivarFlags() async {
    try {
      await _canal.invokeMethod<void>('desactivarFlags');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudieron desactivar los flags de la alarma: $e');
      }
    }
  }

  /// Cancela solo las notificaciones mostradas, sin tocar las alarmas
  /// semanales que siguen programadas en Android.
  Future<void> cancelarNotificaciones(Iterable<int> ids) async {
    final lista = ids.where((id) => id > 0).toSet().toList();
    if (lista.isEmpty) return;
    try {
      await _canal.invokeMethod<void>(
        'cancelarNotificaciones',
        {'ids': lista},
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo cancelar la notificación de la alarma: $e');
      }
    }
  }
}
