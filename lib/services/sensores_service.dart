import 'package:ambient_light/ambient_light.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:vibration/vibration.dart';

/// Sensores nativos para la pantalla de alarma:
///  - Vibración fuerte y sostenida.
///  - Sensor de luz ambiental + brillo de pantalla al máximo.
class SensoresService {
  static final SensoresService _instancia = SensoresService._interno();
  factory SensoresService() => _instancia;
  SensoresService._interno();

  /// Canal nativo (MainActivity) para consultar/abrir el permiso especial
  /// WRITE_SETTINGS. El plugin screen_brightness no expone "abrir ajustes".
  static const MethodChannel _canalAjustes =
      MethodChannel('com.mediplan.mediplan/ajustes_escritura');

  final AmbientLight _ambientLight = AmbientLight();

  /// Brillo del sistema previo a la alarma, para restaurarlo al salir.
  double? _brilloSistemaPrevio;

  /// Evita reabrir la pantalla de ajustes más de una vez por sesión.
  bool _avisoPermisoBrilloMostrado = false;

  /// Lee la luz ambiental actual en lux. Devuelve null si no está disponible.
  Future<double?> luzAmbientalActual() async {
    try {
      return await _ambientLight.currentAmbientLight();
    } catch (_) {
      return null;
    }
  }

  /// True si la app puede cambiar el brillo del sistema. En Android exige el
  /// permiso especial WRITE_SETTINGS; en plataformas que no lo piden
  /// (iOS/desktop) se asume permitido.
  Future<bool> puedeCambiarBrilloSistema() async {
    try {
      return await ScreenBrightness.instance.canChangeSystemBrightness;
    } catch (_) {
      return true;
    }
  }

  /// Si falta el permiso WRITE_SETTINGS, abre la pantalla del sistema
  /// ("Modificar las configuraciones del sistema") apuntando a MediPlan, en vez
  /// de fallar en silencio. No hace nada si ya está concedido, si la plataforma
  /// no aplica (iOS/desktop) o si ya se avisó en esta sesión.
  Future<void> asegurarPermisoBrillo() async {
    if (await puedeCambiarBrilloSistema()) return;
    if (_avisoPermisoBrilloMostrado) return;
    _avisoPermisoBrilloMostrado = true;
    try {
      await _canalAjustes.invokeMethod<void>('abrirAjustesEscritura');
    } catch (_) {
      // Sin canal nativo (iOS/desktop) o si no se pudo abrir: no es fatal.
    }
  }

  /// Sube el brillo de pantalla al máximo del sistema. Requiere WRITE_SETTINGS:
  /// si falta el permiso no cambia nada y deja que [asegurarPermisoBrillo] lo
  /// solicite. Guarda el brillo previo para poder restaurarlo.
  Future<void> subirBrilloAlMaximo() async {
    try {
      if (!await puedeCambiarBrilloSistema()) return;
      _brilloSistemaPrevio ??= await ScreenBrightness.instance.system;
      await ScreenBrightness.instance.setSystemScreenBrightness(1.0);
    } catch (_) {
      // Si el método falla en la plataforma, simplemente seguimos.
    }
  }

  /// Restaura el brillo del sistema al valor previo a la alarma y limpia el
  /// override de la aplicación.
  Future<void> restaurarBrillo() async {
    try {
      final previo = _brilloSistemaPrevio;
      if (previo != null) {
        await ScreenBrightness.instance.setSystemScreenBrightness(previo);
        _brilloSistemaPrevio = null;
      }
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {
      // Si falla, seguimos.
    }
  }

  /// Vibración fuerte y sostenida. Si la plataforma soporta control de
  /// duración/amplitud, vibra a máxima intensidad durante un tiempo largo;
  /// de lo contrario emite pulsos repetidos.
  Future<void> vibrarFuerteYContinuo() async {
    final tieneVibrador = await Vibration.hasVibrator();
    if (tieneVibrador != true) return;

    try {
      final custom = await Vibration.hasCustomVibrationsSupport();
      if (custom == true) {
        Vibration.vibrate(duration: 5000, amplitude: 255);
      } else {
        // Pulso único; la repetición la mantiene la pantalla de alarma.
        Vibration.vibrate(duration: 1000, amplitude: 255);
      }
    } catch (_) {
      Vibration.vibrate();
    }
  }

  /// Detiene la vibración en curso.
  Future<void> detenerVibracion() async {
    try {
      Vibration.cancel();
    } catch (_) {
      // noop
    }
  }
}
