import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/vinculacion_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_page_route.dart';
import '../../utils/errores_amigables.dart';
import '../../utils/validacion_ficha_paciente.dart';
import '../../widgets/formulario_ficha_paciente.dart';
import 'detalle_paciente_screen.dart';

/// Crea un paciente nuevo, genera su código de vinculación único y lo muestra
/// para que el cuidador lo comparta con el paciente.
///
/// Los campos de ficha (edad, condición, contacto de emergencia y foto) son
/// opcionales: solo se guardan si el cuidador los rellena.
class NuevoPacienteScreen extends StatefulWidget {
  const NuevoPacienteScreen({super.key});

  @override
  State<NuevoPacienteScreen> createState() => _NuevoPacienteScreenState();
}

class _NuevoPacienteScreenState extends State<NuevoPacienteScreen> {
  final VinculacionService _vinculacion = VinculacionService();

  final _nombreController = TextEditingController();
  final _edadController = TextEditingController();
  final _condicionController = TextEditingController();
  final _contactoController = TextEditingController();
  String? _fotoBase64;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _edadController.dispose();
    _condicionController.dispose();
    _contactoController.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_cargando) return;
    final resultado = validarFichaPaciente(
      nombre: _nombreController.text,
      edad: _edadController.text,
      condicion: _condicionController.text,
      contactoEmergencia: _contactoController.text,
    );
    if (!resultado.esValida) {
      setState(() => _error = resultado.error);
      return;
    }
    final datos = resultado.datos!;

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pacienteId = await _vinculacion.crearPacienteConCodigo(
        datos.nombre,
        edad: datos.edad,
        condicion: datos.condicion,
        contactoEmergencia: datos.contactoEmergencia,
        fotoBase64: _fotoBase64,
      );
      _nombreController.clear();
      HapticFeedback.lightImpact();
      // Abrimos el detalle que mostrará el código recién generado.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          AppPageRoute(builder: (_) => DetallePacienteScreen.porId(pacienteId)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mensajeErrorAmigable(e, contexto: 'Error creando paciente');
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo paciente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.person_add, size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text(
              '¿Cómo se llama el paciente?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FormularioFichaPaciente(
              nombreController: _nombreController,
              edadController: _edadController,
              condicionController: _condicionController,
              contactoController: _contactoController,
              fotoBase64: _fotoBase64,
              onFotoCambiada: (foto) => setState(() => _fotoBase64 = foto),
              permitirQuitarFoto: true,
              habilitado: !_cargando,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _cargando ? null : _crear,
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
                    : const Text(
                        'Generar código',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Verá el código para compartir con el paciente en el siguiente paso.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
