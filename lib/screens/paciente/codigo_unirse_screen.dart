import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/vinculacion_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';

/// Pantalla del rol Paciente: ingresa el código que le dio su cuidador.
/// No requiere login; el vínculo se persiste localmente.
class CodigoUnirseScreen extends StatefulWidget {
  const CodigoUnirseScreen({super.key});

  @override
  State<CodigoUnirseScreen> createState() => _CodigoUnirseScreenState();
}

class _CodigoUnirseScreenState extends State<CodigoUnirseScreen> {
  final VinculacionService _vinculacion = VinculacionService();
  final _codigoController = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _unirse() async {
    if (_cargando) return;
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      setState(() => _error = 'Escribí el código que te dio tu cuidador.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final error = await _vinculacion.vincularPaciente(codigo);
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _error = error;
          _cargando = false;
        });
        return;
      }
      // Recargamos el estado para pasar al flujo de paciente.
      await context.read<AppState>().cargarEstadoInicial();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseException catch (e, st) {
      // El detalle técnico queda solo en el log. Al paciente no se le muestra
      // el texto de Firestore.
      if (kDebugMode) {
        debugPrint('Error de Firebase al vincular (${e.code}): $e\n$st');
      }
      _mostrarErrorDeVinculacion();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error inesperado al vincular: $e\n$st');
      }
      _mostrarErrorDeVinculacion();
    }
  }

  void _mostrarErrorDeVinculacion() {
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error =
          'No pudimos verificar el código. '
          'Revisa tu conexión e inténtalo de nuevo.';
    });
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
                  Icons.link,
                  size: AppSizes.iconXLarge + AppSizes.icon,
                  color: AppColors.accent,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Código para unirse',
                  textAlign: TextAlign.center,
                  style: AppType.title.copyWith(color: AppColors.onGreen),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tu cuidador te dio un código.\nEscríbelo acá para empezar.',
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(color: AppColors.onGreen),
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        TextField(
                          controller: _codigoController,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: AppType.display.copyWith(
                            color: AppColors.onGreen,
                            letterSpacing: 3,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'MEDI-XXXXXX',
                          ),
                          onSubmitted: (_) => _unirse(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: AppType.label.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _cargando ? null : _unirse,
                            child: _cargando
                                ? const SizedBox(
                                    width: AppSizes.icon,
                                    height: AppSizes.icon,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onAccent,
                                    ),
                                  )
                                : const Text('Unirme'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.onGreen,
                    minimumSize: const Size(
                      AppSizes.minTouch,
                      AppSizes.minTouch,
                    ),
                  ),
                  child: const Text('Atrás'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
