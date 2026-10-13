import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'screens/seleccion_rol_screen.dart';
import 'screens/doctor/dashboard_screen.dart';
import 'screens/paciente/medicamentos_proximos_screen.dart';
import 'services/notificaciones_service.dart';
import 'services/push_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/app_logo.dart';

/// Raíz de la aplicación: decide el punto de entrada según el rol.
class MediPlanApp extends StatelessWidget {
  const MediPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediPlan',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const BootstrapScreen(),
    );
  }
}

/// Pantalla de arranque: inicializa Firebase y el resto de servicios ANTES de
/// mostrar la UI del rol. Mientras tanto renderiza un splash; si algo falla,
/// muestra el error en pantalla con opción de reintentar (en vez de dejar la
/// app en negro sin explicación).
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  final AppState _appState = AppState();
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Inicializa Firebase (ver firebase_options.dart: correr `flutterfire configure`).
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Inicializa y pide permiso para notificaciones locales de alarma.
      final notif = NotificacionesService();
      await notif.inicializar();
      await notif.pedirPermiso();

      // Deja listo el push paciente → cuidador. Si no hay credencial en
      // `assets/secrets/`, el push queda desactivado y la app sigue igual.
      await PushService().inicializar();

      await _appState.cargarEstadoInicial();
    } catch (e) {
      debugPrint('Error de inicialización de MediPlan: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.toString();
        });
      }
      return;
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        // Mismo verde que el splash nativo y que la selección de rol: el logo
        // (ahora con transparencia real) se apoya directamente sobre él.
        backgroundColor: AppColors.primary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(tamanoLogo: 96, tamanoTexto: 32),
                const SizedBox(height: 24),
                Icon(Icons.error_outline, size: 64, color: AppColors.error),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo iniciar la app',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _inicializar,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_cargando) {
      return Scaffold(
        // Verde principal (coincide con el color del splash nativo): el logo
        // transparente se muestra directamente sobre él, sin caja detrás.
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(tamanoLogo: 112, tamanoTexto: 38),
              const SizedBox(height: 32),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Preparando MediPlan...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 48),
              const Text(
                '© 2025 MediPlan. Todos los derechos reservados.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _appState,
      child: const HomeRouter(),
    );
  }
}

/// Decide qué pantalla mostrar según el estado de la app.
class HomeRouter extends StatelessWidget {
  const HomeRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.cargandoPaciente) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final usuario = snap.data;
        // Un cuidador con credenciales (sesión NO anónima) tiene prioridad:
        // un login de cuidador nunca queda bloqueado por el flag de paciente.
        if (usuario != null && !usuario.isAnonymous) {
          return const DashboardScreen();
        }
        // Paciente ya vinculado (sesión anónima) → va directo a sus medicamentos.
        if (appState.esPaciente) {
          return const MedicamentosProximosScreen();
        }
        return const SeleccionRolScreen();
      },
    );
  }
}
