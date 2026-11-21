import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/local_store.dart';
import 'services/sincronizacion_paciente_service.dart';
import 'utils/errores_amigables.dart';

/// Manejador de FCM con la app cerrada. Es una función de nivel superior para
/// que `firebase_messaging` pueda aislarla en su propio isolate.
@pragma('vm:entry-point')
Future<void> manejarMensajeSincronizacionFondo(RemoteMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await configurarZonaHorariaSegundoPlano();
    await SincronizacionPacienteService().procesarMensaje(
      message.data,
      prepararNotificaciones: true,
    );
  } catch (e) {
    try {
      await LocalStore.guardarUltimoErrorSincronizacion(
        mensajeErrorAmigable(
          e,
          contexto: 'No se pudo sincronizar el cambio de tratamiento',
        ),
      );
    } catch (_) {
      // El último error es informativo y nunca debe tumbar el isolate.
    }
  }
}

/// La inicialización de Firebase y las notificaciones se delega a
/// BootstrapScreen (en app.dart), que muestra un splash mientras tanto y el
/// error en pantalla si algo falla. Así `runApp` se ejecuta de inmediato y la
/// app nunca queda en pantalla negra.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(manejarMensajeSincronizacionFondo);
  runApp(const MediPlanApp());
}
