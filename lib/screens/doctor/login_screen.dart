import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/local_store.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/errores_amigables.dart';
import '../../widgets/boton_cargando.dart';
import '../../widgets/snackbars.dart';

/// Pantalla de bienvenida y login del Cuidador/Doctor.
/// Acceso con correo/contraseña y con Google, más registro de cuenta.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Se crea al primer uso para que el widget se pueda montar en pruebas sin
  // inicializar Firebase.
  AuthService? _authCache;
  AuthService get _auth => _authCache ??= AuthService();

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();

  bool _esRegistro = false;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_cargando) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_esRegistro) {
        await _auth.registrar(
          _nombreController.text.trim(),
          _correoController.text.trim(),
          _contrasenaController.text,
        );
        await _auth.guardarPerfilUsuario(nombre: _nombreController.text.trim());
      } else {
        await _auth.iniciarSesion(
          _correoController.text.trim(),
          _contrasenaController.text,
        );
      }
      // Al iniciar sesión: el StreamBuilder de HomeRouter reacciona al cambio de auth.
      // Un login de cuidador exitoso limpia el flag/LocalStore de paciente que
      // hubiera quedado en este dispositivo. No usamos AppState: las rutas
      // abiertas con Navigator.push no ven su provider.
      if (mounted) {
        // Limpieza única de alarmas de medicamentos que versiones anteriores
        // dejaron programadas en el teléfono del cuidador.
        await NotificacionesService().migrarAlarmasDeCuidador();
        await LocalStore.limpiarPacienteVinculado();
        if (mounted) Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(e, contexto: 'Error de autenticación'),
        );
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(
            e,
            contexto: 'Error inesperado al iniciar sesión',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _google() async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final ok = await _auth.iniciarSesionConGoogle();
      if (ok) {
        await _auth.guardarPerfilUsuario();
        if (mounted) {
          await NotificacionesService().migrarAlarmasDeCuidador();
          await LocalStore.limpiarPacienteVinculado();
          if (mounted) Navigator.of(context).pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(
            e,
            contexto: 'Error de autenticación con Google',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(e, contexto: 'Error inesperado con Google'),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                const Icon(
                  Icons.medical_services_rounded,
                  size: AppSizes.iconXLarge + AppSizes.icon,
                  color: AppColors.accent,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Welcome back',
                  style: AppType.display.copyWith(color: AppColors.onGreen),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _esRegistro ? 'Crea tu cuenta de doctor' : 'Inicia sesión',
                  style: AppType.body.copyWith(color: AppColors.onGreen),
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_esRegistro) ...[
                            TextFormField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Ingresa tu nombre'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          TextFormField(
                            controller: _correoController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Correo',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Correo inválido'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _contrasenaController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Mínimo 6 caracteres'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _error!,
                              style: AppType.label.copyWith(
                                color: AppColors.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          BotonCargando(
                            cargando: _cargando,
                            onPressed: _enviar,
                            texto: _esRegistro ? 'Registrarme' : 'Entrar',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                                child: Text(
                                  'o',
                                  style: AppType.label.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _cargando ? null : _google,
                              icon: const Icon(
                                Icons.g_mobiledata,
                                size: AppSizes.iconLarge,
                              ),
                              label: const Text('Continuar con Google'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _esRegistro = !_esRegistro;
                                _error = null;
                              });
                            },
                            child: Text(
                              _esRegistro
                                  ? 'Ya tengo cuenta'
                                  : '¿No tienes cuenta? Regístrate',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
