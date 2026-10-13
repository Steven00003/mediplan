import 'package:flutter/material.dart';

import 'app.dart';

/// La inicialización de Firebase y las notificaciones se delega a
/// BootstrapScreen (en app.dart), que muestra un splash mientras tanto y el
/// error en pantalla si algo falla. Así `runApp` se ejecuta de inmediato y la
/// app nunca queda en pantalla negra.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MediPlanApp());
}
