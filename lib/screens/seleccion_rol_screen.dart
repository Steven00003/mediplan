import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/confirmar_salida_app.dart';
import 'doctor/login_screen.dart';
import 'paciente/codigo_unirse_screen.dart';

/// URL temporal del sitio del proyecto (mientras el equipo crea la página
/// propia). Se abre en el navegador externo al tocar el logo.
/// TODO: reemplazar por la página propia del proyecto.
const _urlProyecto = 'https://www.uts.edu.co';

/// Pantalla inicial: el usuario elige su rol.
///
/// - "Paciente" → pantalla de código para unirse (sin login).
/// - "Doctor" → pantalla de login (Firebase Auth).
class SeleccionRolScreen extends StatelessWidget {
  const SeleccionRolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ConfirmarSalidaApp(
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Huevo de pascua: tocar el logo abre la página del proyecto en
                // el navegador externo. Sin indicador visual a propósito.
                GestureDetector(
                  onTap: () => _abrirPaginaProyecto(context),
                  child: const AppLogo(
                    tamanoLogo: 120,
                    tamanoTexto: 40,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '¿Quién es?',
                  style: TextStyle(
                    color: AppColors.onGreen,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 48),
                _BotonRol(
                  icono: Icons.person,
                  titulo: 'Paciente',
                  descripcion: 'Tomo mis medicinas',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        // Las rutas push NO heredan el provider de HomeRouter;
                        // re-exponemos el mismo AppState para que la pantalla
                        // pueda leerlo.
                        builder: (_) => ChangeNotifierProvider<AppState>.value(
                          value: context.read<AppState>(),
                          child: const CodigoUnirseScreen(),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _BotonRol(
                  icono: Icons.medical_services,
                  titulo: 'Doctor',
                  descripcion: 'Cuido a mis pacientes',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Abre la página del proyecto en el navegador externo del teléfono.
  /// Fallo silencioso salvo un aviso breve: no debe romper el flujo de rol.
  Future<void> _abrirPaginaProyecto(BuildContext context) async {
    try {
      await launchUrl(
        Uri.parse(_urlProyecto),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Sin navegador disponible u otro error de lanzamiento.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace')),
        );
      }
    }
  }
}

class _BotonRol extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _BotonRol({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 100,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(icono, size: 48, color: AppColors.accent),
                const SizedBox(width: 20),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onGreen,
                      ),
                    ),
                    Text(
                      descripcion,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
