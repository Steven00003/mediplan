import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/local_store.dart';
import '../../theme/app_colors.dart';

/// Pantalla de bienvenida y login del Cuidador/Doctor.
/// Acceso con correo/contraseña y con Google, más registro de cuenta.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();

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
        if (kDebugMode) {
          debugPrint('Cuenta creada');
        }
      } else {
        await _auth.iniciarSesion(
          _correoController.text.trim(),
          _contrasenaController.text,
        );
      }
      // Alectar: el StreamBuilder de HomeRouter reacciona al cambio de auth.
      // Un login de cuidador exitoso limpia el flag/LocalStore de paciente que
      // hubiera quedado en este dispositivo. No usamos AppState: las rutas
      // abiertas con Navigator.push no ven su provider.
      if (mounted) {
        await LocalStore.limpiarPacienteVinculado();
        if (mounted) Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('Error login: ${e.code}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error login: ${e.code}')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error login: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error login: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final ok = await _auth.iniciarSesionConGoogle();
      if (ok) {
        await _auth.guardarPerfilUsuario();
        if (mounted) {
          await LocalStore.limpiarPacienteVinculado();
          if (mounted) Navigator.of(context).pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('Error login: ${e.code}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error login: ${e.code}')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error login: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error login: $e')),
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
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.medical_services_rounded,
                    size: 72, color: AppColors.accent),
                const SizedBox(height: 8),
                const Text(
                  'Welcome back',
                  style: TextStyle(
                    color: AppColors.onGreen,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _esRegistro ? 'Crea tu cuenta de doctor' : 'Inicia sesión',
                  style: const TextStyle(
                    color: AppColors.onGreen,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
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
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _correoController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) =>
                              (v == null || !v.contains('@'))
                                  ? 'Correo inválido'
                                  : null,
                        ),
                        const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _cargando ? null : _enviar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.onAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _cargando
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onAccent,
                                    ),
                                  )
                                : Text(
                                    _esRegistro ? 'Registrarme' : 'Entrar',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('o'),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _cargando ? null : _google,
                            icon: const Icon(Icons.g_mobiledata, size: 30),
                            label: const Text(
                              'Continuar con Google',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
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
