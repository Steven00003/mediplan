import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_state.dart';
import '../services/local_store.dart';
import '../theme/app_colors.dart';
import '../utils/reingreso_paciente.dart';
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
/// - Si el dispositivo recuerda una vinculación, ofrece "Continuar como
///   paciente" sin pedir el código.
/// - "Paciente" → pantalla de código para unirse (sin login).
/// - "Doctor" → pantalla de login (Firebase Auth).
class SeleccionRolScreen extends StatefulWidget {
  const SeleccionRolScreen({super.key});

  @override
  State<SeleccionRolScreen> createState() => _SeleccionRolScreenState();
}

class _SeleccionRolScreenState extends State<SeleccionRolScreen> {
  VinculacionRecordada? _recordada;
  bool _ingresando = false;

  @override
  void initState() {
    super.initState();
    _cargarRecordada();
  }

  Future<void> _cargarRecordada() async {
    VinculacionRecordada? recordada;
    try {
      recordada = await LocalStore.getUltimaVinculacion();
    } catch (_) {
      // Sin SharedPreferences (tests/plataformas no soportadas) se comporta
      // como si no hubiera vinculación recordada.
      recordada = null;
    }
    if (!mounted) return;
    setState(() => _recordada = recordada);
  }

  bool get _ofrecerContinuar => debeOfrecerContinuarComoPaciente(
        recordada: _recordada,
        pacienteActivo: false,
        sesionCuidador: false,
      );

  String get _descripcionContinuar {
    if (_ingresando) return 'Ingresando...';
    final nombre = _recordada?.nombre.trim() ?? '';
    if (nombre.isEmpty) return 'Volver sin escribir el código';
    return '$nombre · Volver sin código';
  }

  Future<void> _continuarComoPaciente() async {
    if (_ingresando) return;
    setState(() => _ingresando = true);
    final resultado = await context.read<AppState>().reingresarPaciente();
    if (!mounted) return;
    setState(() => _ingresando = false);

    switch (resultado) {
      case ResultadoReingresoPaciente.exito:
        // HomeRouter cambia al flujo de paciente al notificar AppState.
        break;
      case ResultadoReingresoPaciente.sinVinculacionRecordada:
        await _cargarRecordada();
        if (mounted) {
          _mostrar('No hay una vinculación guardada. Escribe el código.');
        }
        break;
      case ResultadoReingresoPaciente.noCoincide:
        await _cargarRecordada();
        if (mounted) {
          _mostrar('La vinculación ya no está activa. Escribe el código.');
        }
        break;
      case ResultadoReingresoPaciente.errorRed:
        _mostrar(
          'No se pudo conectar. Revisa tu internet e intenta de nuevo.',
        );
        break;
    }
  }

  Future<void> _usarOtroCodigo() async {
    if (_ingresando) return;
    try {
      await LocalStore.limpiarUltimaVinculacion();
    } catch (_) {
      // Si falla el almacenamiento, igual se abre el código; la vinculación
      // recordada se volverá a evaluar al regresar.
    }
    if (!mounted) return;
    setState(() => _recordada = null);
    _abrirCodigo();
  }

  void _abrirCodigo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        // Las rutas push NO heredan el provider de HomeRouter; re-exponemos el
        // mismo AppState para que la pantalla pueda leerlo.
        builder: (_) => ChangeNotifierProvider<AppState>.value(
          value: context.read<AppState>(),
          child: const CodigoUnirseScreen(),
        ),
      ),
    );
  }

  void _abrirLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  void _mostrar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

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
                if (_ofrecerContinuar) ...[
                  _BotonRol(
                    icono: Icons.person,
                    titulo: 'Continuar como paciente',
                    descripcion: _descripcionContinuar,
                    tamanoTitulo: 22,
                    cargando: _ingresando,
                    onTap: _ingresando ? null : _continuarComoPaciente,
                  ),
                  TextButton(
                    onPressed: _ingresando ? null : _usarOtroCodigo,
                    child: const Text(
                      'Usar otro código',
                      style: TextStyle(
                        color: AppColors.onGreen,
                        fontSize: 16,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  _BotonRol(
                    icono: Icons.person,
                    titulo: 'Paciente',
                    descripcion: 'Tomo mis medicinas',
                    onTap: _abrirCodigo,
                  ),
                  const SizedBox(height: 20),
                ],
                _BotonRol(
                  icono: Icons.medical_services,
                  titulo: 'Doctor',
                  descripcion: 'Cuido a mis pacientes',
                  onTap: _abrirLogin,
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
  final VoidCallback? onTap;
  final double tamanoTitulo;
  final bool cargando;

  const _BotonRol({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
    this.tamanoTitulo = 26,
    this.cargando = false,
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
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: tamanoTitulo,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onGreen,
                        ),
                      ),
                      Text(
                        descripcion,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (cargando)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
