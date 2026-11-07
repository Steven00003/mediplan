import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'screens/seleccion_rol_screen.dart';
import 'screens/doctor/dashboard_screen.dart';
import 'screens/paciente/alarma_screen.dart';
import 'screens/paciente/medicamentos_proximos_screen.dart';
import 'services/firestore_service.dart';
import 'services/notificaciones_service.dart';
import 'services/push_service.dart';
import 'services/ventana_alarma_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'utils/vigencia_tratamiento.dart';
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
  final NotificacionesService _notif = NotificacionesService();
  final FirestoreService _fs = FirestoreService();
  final VentanaAlarmaService _ventanaAlarma = const VentanaAlarmaService();
  bool _cargando = true;
  String? _error;
  bool _procesandoPayload = false;

  @override
  void initState() {
    super.initState();
    _notif.payloadPendiente.addListener(_alCambiarPayload);
    _inicializar();
  }

  @override
  void dispose() {
    _notif.payloadPendiente.removeListener(_alCambiarPayload);
    super.dispose();
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
      await _notif.inicializar();
      await _notif.pedirPermiso();

      // Deja listo el push paciente → cuidador. Si no hay credencial en
      // `assets/secrets/`, el push queda desactivado y la app sigue igual.
      await PushService().inicializar();

      await _appState.cargarEstadoInicial();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error de inicialización de MediPlan: $e');
      }
      // Si la app venía de una notificación, no dejamos la ventana con los
      // flags de alarma mientras se muestra la pantalla de error.
      await _ventanaAlarma.desactivarFlags();
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.toString();
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _cargando = false);

    // La alarma se abre después de que HomeRouter ya esté montado. Si el
    // payload llegó durante el arranque, queda guardado hasta este momento.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_procesarPayloadPendiente());
    });
  }

  void _alCambiarPayload() {
    if (_error != null) {
      // La app no llegó a cargar: se descarta el toque y se liberan los flags
      // que MainActivity pudo activar al abrir la notificación.
      _notif.tomarPayloadPendiente();
      unawaited(_ventanaAlarma.desactivarFlags());
      return;
    }
    if (_cargando || _appState.cargandoPaciente) return;

    // Si ya hay una alarma en pantalla (o se está abriendo), este toque no
    // debe abrir una segunda. Se descarta el payload.
    if (_procesandoPayload || _appState.alarmaAbierta) {
      _notif.tomarPayloadPendiente();
      return;
    }
    unawaited(_procesarPayloadPendiente());
  }

  /// Libera los flags nativos si el payload no se puede convertir en alarma.
  /// No los toca si ya hay otra alarma visible: esos flags son suyos.
  Future<void> _descartarPayloadInvalido() async {
    if (_appState.alarmaAbierta) return;
    await _ventanaAlarma.desactivarFlags();
  }

  /// Abre la alarma indicada por el payload `tratamientoId|HH:mm`.
  ///
  /// Cualquier payload inválido o de otro paciente se ignora: el arranque de
  /// la app nunca debe fallar por una notificación vieja o manipulada.
  Future<void> _procesarPayloadPendiente() async {
    if (_procesandoPayload ||
        _error != null ||
        _cargando ||
        _appState.cargandoPaciente) {
      return;
    }

    final pendiente = _notif.tomarPayloadPendiente();
    if (pendiente == null) return;
    final payload = pendiente.payload;

    _procesandoPayload = true;
    try {
      final pacienteId = _appState.pacienteVinculado?.id;
      final usuario = FirebaseAuth.instance.currentUser;
      if (pacienteId == null || usuario == null || !usuario.isAnonymous) {
        await _descartarPayloadInvalido();
        return;
      }

      final partes = payload.split('|');
      if (partes.length != 2) {
        if (kDebugMode) {
          debugPrint('Payload de alarma inválido');
        }
        await _descartarPayloadInvalido();
        return;
      }
      final tratamientoId = partes[0].trim();
      final hora = _horaDesdePayload(partes[1].trim());
      if (tratamientoId.isEmpty || hora == null) {
        if (kDebugMode) {
          debugPrint('Payload de alarma inválido');
        }
        await _descartarPayloadInvalido();
        return;
      }

      final tratamiento = await _fs.getTratamiento(tratamientoId);
      if (!mounted) return;

      // Solo el paciente vinculado puede abrir tratamientos suyos. Un payload
      // con el id de otro paciente se ignora.
      if (tratamiento == null || tratamiento.pacienteId != pacienteId) {
        if (kDebugMode) {
          debugPrint(
            'Alarma ignorada: el tratamiento no existe o es de otro paciente',
          );
        }
        await _descartarPayloadInvalido();
        return;
      }

      // Una alarma recurrente puede dispararse antes de que la reconciliación
      // alcance a cancelarla (p. ej. el paciente no abrió la app en días). El
      // toque no debe abrir una alarma de un tratamiento ya terminado.
      if (!VigenciaTratamiento.estaVigente(tratamiento, DateTime.now())) {
        if (kDebugMode) {
          debugPrint(
            'Alarma ignorada: el tratamiento ya terminó. '
            'Se cancelan sus notificaciones.',
          );
        }
        await _notif.cancelarNotificacionesDeTratamiento(
          tratamientoId: tratamiento.id,
          horarios: tratamiento.horarios,
        );
        await _descartarPayloadInvalido();
        return;
      }

      if (_appState.pacienteVinculado?.id != pacienteId) {
        await _descartarPayloadInvalido();
        return;
      }
      if (_appState.alarmaAbierta) return;

      _appState.setAlarmaAbierta(true);
      try {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlarmaScreen(
              tratamiento: tratamiento,
              horaProgramada: hora,
              pacienteId: pacienteId,
              idNotificacion: pendiente.idNotificacion,
            ),
          ),
        );
      } finally {
        _appState.setAlarmaAbierta(false);
      }
    } catch (e) {
      // Un tap sobre una notificación vieja no puede tumbar el arranque.
      if (kDebugMode) {
        debugPrint('No se pudo abrir la alarma desde la notificación: $e');
      }
      await _descartarPayloadInvalido();
    } finally {
      _procesandoPayload = false;
    }
  }

  TimeOfDay? _horaDesdePayload(String valor) {
    final partes = valor.split(':');
    if (partes.length != 2) return null;
    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);
    if (hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      return null;
    }
    return TimeOfDay(hour: hora, minute: minuto);
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
