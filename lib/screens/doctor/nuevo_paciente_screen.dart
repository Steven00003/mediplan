import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/imagen_service.dart';
import '../../services/vinculacion_service.dart';
import '../../theme/app_colors.dart';
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
  final ImagenService _imagen = ImagenService();
  final ImagePicker _picker = ImagePicker();

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

  Future<void> _elegirFoto() async {
    final foto = await _picker.pickImage(source: ImageSource.gallery);
    if (foto == null) return;
    setState(() => _cargando = true);
    try {
      final bytes = await foto.readAsBytes();
      final base64 = await _imagen.fotoABase64(bytes);
      if (!mounted) return;
      setState(() {
        _fotoBase64 = base64;
        _cargando = false;
      });
      if (base64 == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo procesar la foto. Elige otra.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error foto: $e');
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar la foto: $e')),
      );
    }
  }

  Future<void> _crear() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa el nombre del paciente.');
      return;
    }

    // Edad opcional: si viene texto, tiene que ser un entero válido.
    int? edad;
    final edadTxt = _edadController.text.trim();
    if (edadTxt.isNotEmpty) {
      edad = int.tryParse(edadTxt);
      if (edad == null || edad < 0) {
        setState(() => _error = 'Ingresa una edad válida.');
        return;
      }
    }

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pacienteId = await _vinculacion.crearPacienteConCodigo(
        nombre,
        edad: edad,
        condicion: _vacioANull(_condicionController.text),
        contactoEmergencia: _vacioANull(_contactoController.text),
        fotoBase64: _fotoBase64,
      );
      _nombreController.clear();
      // Abrimos el detalle que mostrará el código recién generado.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DetallePacienteScreen.porId(pacienteId),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error al crear paciente: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el paciente: $e')),
      );
      setState(() => _error = 'No se pudo crear el paciente.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Un campo de texto vacío se guarda como null, no como "".
  String? _vacioANull(String texto) {
    final t = texto.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo paciente'),
      ),
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
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre del paciente',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _edadController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(
                labelText: 'Edad',
                hintText: 'Ej: 78',
                helperText: 'Opcional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _condicionController,
              decoration: const InputDecoration(
                labelText: 'Condición médica',
                hintText: 'Ej: Alzheimer, Hipertensión',
                helperText: 'Opcional',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactoController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contacto de emergencia',
                hintText: '+34 600 000 000',
                helperText: 'Opcional',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 20),
            _fotoWidget(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: AppColors.error),
              ),
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
                    : const Text('Generar código',
                        style: TextStyle(fontSize: 18)),
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

  /// Foto de perfil del paciente. Se reutiliza [ImagenService], igual que la
  /// foto de los medicamentos: base64 dentro del propio documento, sin Storage.
  Widget _fotoWidget() {
    Widget contenido;
    if (_cargando) {
      contenido = const Center(child: CircularProgressIndicator());
    } else if (_fotoBase64 != null && _fotoBase64!.isNotEmpty) {
      final bytes = ImagenService.decodificar(_fotoBase64!);
      contenido = bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                bytes,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _IconoFotoPaciente(),
              ),
            )
          : const _IconoFotoPaciente();
    } else {
      contenido = const _IconoFotoPaciente();
    }
    return GestureDetector(
      onTap: _cargando ? null : _elegirFoto,
      child: Column(
        children: [
          contenido,
          const SizedBox(height: 8),
          const Text(
            'Toca para elegir una foto (opcional)',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _IconoFotoPaciente extends StatelessWidget {
  const _IconoFotoPaciente();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.add_a_photo, size: 36, color: AppColors.accent),
    );
  }
}
