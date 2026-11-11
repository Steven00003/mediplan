import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/local_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_page_route.dart';
import '../theme/app_tokens.dart';
import '../utils/abrir_landing.dart';
import '../utils/reingreso_paciente.dart';
import '../widgets/app_logo.dart';
import '../widgets/confirmar_salida_app.dart';
import '../widgets/menu_ayuda.dart';
import 'doctor/login_screen.dart';
import 'paciente/codigo_unirse_screen.dart';

/// Pantalla inicial: el usuario elige su rol.
///
/// - Si el dispositivo recuerda una vinculación, ofrece entrar directamente
///   como ese paciente sin pedir el código.
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

  String get _nombre => _recordada?.nombre.trim() ?? '';

  String get _saludo => _nombre.isEmpty ? 'Hola' : 'Hola, $_nombre';

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
        _mostrar('No se pudo conectar. Revisa tu internet e intenta de nuevo.');
        break;
    }
  }

  /// Pide confirmación antes de olvidar la vinculación recordada.
  ///
  /// La lógica de salida no cambia: solo se llama a [_usarOtroCodigo] cuando
  /// el usuario confirma explícitamente.
  Future<void> _confirmarUsarOtroCodigo() async {
    if (_ingresando) return;
    final nombre = _nombre;
    final continuar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Usar otro código?'),
        content: Text(
          nombre.isEmpty
              ? 'Este celular olvidará la vinculación recordada y tendrás '
                    'que escribir un código para volver a entrar.'
              : 'Este celular olvidará a $nombre y tendrás que escribir un '
                    'código para volver a entrar.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // La acción destructiva (olvidar la vinculación) queda pequeña y
          // secundaria; "Cancelar" es la opción grande y enfocada por defecto.
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Continuar'),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (continuar == true) {
      await _usarOtroCodigo();
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
      AppPageRoute(
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
    Navigator.of(context)
        .push(AppPageRoute(builder: (_) => const LoginScreen()));
  }

  void _mostrar(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmarSalidaApp(
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // SingleChildScrollView + IntrinsicHeight permiten que la
                    // pantalla se centre cuando sobra espacio y haga scroll cuando
                    // no alcanza (pantallas pequeñas o textScale alto).
                    final altoMinimo = constraints.maxHeight - AppSpacing.xxl;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: altoMinimo > 0 ? altoMinimo : 0,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Spacer(flex: 2),
                              // Tocar el logo abre la landing en el navegador
                              // externo. Sin indicador visual a propósito.
                              Semantics(
                                button: true,
                                label: 'Abrir la página del proyecto MediPlan',
                                child: GestureDetector(
                                  onTap: () => abrirLanding(context),
                                  child: const AppLogo(
                                    tamanoLogo: 120,
                                    tamanoTexto: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Semantics(
                                header: true,
                                child: Text(
                                  _ofrecerContinuar ? _saludo : '¿Quién es?',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: AppColors.onGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              if (_ofrecerContinuar) ...[
                                _TarjetaPacienteRecordado(
                                  nombre: _nombre,
                                  cargando: _ingresando,
                                  onTap: _ingresando
                                      ? null
                                      : _continuarComoPaciente,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                _EnlaceOtroCodigo(
                                  nombre: _nombre,
                                  habilitado: !_ingresando,
                                  onTap: _confirmarUsarOtroCodigo,
                                ),
                                const Spacer(flex: 3),
                                const _SeparadorO(),
                                const SizedBox(height: AppSpacing.md),
                                _BotonDoctorSecundario(onTap: _abrirLogin),
                                const SizedBox(height: AppSpacing.xs),
                              ] else ...[
                                _BotonRol(
                                  icono: Icons.person,
                                  titulo: 'Paciente',
                                  descripcion: 'Tomo mis medicinas',
                                  onTap: _abrirCodigo,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _BotonRol(
                                  icono: Icons.medical_services,
                                  titulo: 'Doctor',
                                  descripcion: 'Cuido a mis pacientes',
                                  onTap: _abrirLogin,
                                ),
                                const Spacer(flex: 2),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: const AyudaBoton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta grande de reingreso cuando el dispositivo recuerda al paciente.
class _TarjetaPacienteRecordado extends StatelessWidget {
  final String nombre;
  final bool cargando;
  final VoidCallback? onTap;

  const _TarjetaPacienteRecordado({
    required this.nombre,
    required this.cargando,
    required this.onTap,
  });

  String get _inicial {
    final limpio = nombre.trim();
    if (limpio.isEmpty) return '';
    return String.fromCharCode(limpio.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = nombre.isEmpty
        ? 'Continuar como paciente'
        : 'Entrar como $nombre';
    final etiqueta = '$titulo. Sin escribir código.';

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: etiqueta,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.primaryStrong,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.xxl * 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: AppSizes.avatar / 2,
                    backgroundColor: AppColors.onAccent,
                    child: _inicial.isEmpty
                        ? const Icon(
                            Icons.person,
                            color: AppColors.primaryStrong,
                            size: AppSizes.iconLarge,
                          )
                        : Text(
                            _inicial,
                            style: AppType.title.copyWith(
                              color: AppColors.primaryStrong,
                            ),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            titulo,
                            maxLines: 1,
                            softWrap: false,
                            style: AppType.title.copyWith(
                              color: AppColors.onAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          cargando ? 'Ingresando...' : 'Sin escribir código',
                          maxLines: 2,
                          style: AppType.body.copyWith(
                            color: AppColors.onAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cargando)
                    const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.xs),
                      child: SizedBox(
                        width: AppSizes.icon,
                        height: AppSizes.icon,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace discreto para olvidar la vinculación recordada y usar otro código.
class _EnlaceOtroCodigo extends StatelessWidget {
  final String nombre;
  final bool habilitado;
  final VoidCallback onTap;

  const _EnlaceOtroCodigo({
    required this.nombre,
    required this.habilitado,
    required this.onTap,
  });

  String get _texto => nombre.isEmpty
      ? '¿No eres tú? Usar otro código'
      : '¿No eres $nombre? Usar otro código';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: habilitado ? onTap : null,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.onGreen,
          minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          textStyle: AppType.label.copyWith(
            decoration: TextDecoration.underline,
          ),
        ),
        child: Text(_texto, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Separador visual "o" entre la entrada de paciente y la de doctor.
class _SeparadorO extends StatelessWidget {
  const _SeparadorO();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.onGreen.withValues(alpha: 0.30),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'o',
            style: AppType.label.copyWith(
              color: AppColors.onGreen.withValues(alpha: 0.75),
            ),
          ),
        ),
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.onGreen.withValues(alpha: 0.30),
          ),
        ),
      ],
    );
  }
}

/// Opción Doctor secundaria, más baja y con borde, para la pantalla con
/// vinculación recordada.
class _BotonDoctorSecundario extends StatelessWidget {
  final VoidCallback onTap;

  const _BotonDoctorSecundario({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Doctor. Cuido a mis pacientes.',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          side: BorderSide(
            color: AppColors.primaryStrong.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.xxl + AppSpacing.md,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.medical_services,
                    size: AppSizes.iconLarge,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Doctor',
                          style: AppType.button.copyWith(
                            color: AppColors.onGreen,
                          ),
                        ),
                        Text(
                          'Cuido a mis pacientes',
                          style: AppType.label.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: AppSizes.icon,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonRol extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final VoidCallback? onTap;

  const _BotonRol({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$titulo. $descripcion.',
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.xxl * 2),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      icono,
                      size: AppSizes.iconXLarge,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            maxLines: 2,
                            style: AppType.title.copyWith(
                              color: AppColors.onGreen,
                            ),
                          ),
                          Text(
                            descripcion,
                            maxLines: 2,
                            style: AppType.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
