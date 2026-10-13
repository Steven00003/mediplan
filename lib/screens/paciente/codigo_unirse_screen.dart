import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/vinculacion_service.dart';
import '../../theme/app_colors.dart';

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
    } catch (e, st) {
      debugPrint('Error al vincular: $e\n$st');
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al vincular: $e')),
        );
      }
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
                const Icon(Icons.link, size: 72, color: AppColors.accent),
                const SizedBox(height: 16),
                const Text(
                  'Código para unirse',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.onGreen,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tu cuidador te dio un código.\nEscríbelo acá para empezar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.onGreen, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _codigoController,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'MEDI-XXXXXX',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _unirse(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _cargando ? null : _unirse,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.onAccent,
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
                              : const Text('Unirme',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Atrás',
                      style: TextStyle(
                          color: AppColors.onGreen, fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
