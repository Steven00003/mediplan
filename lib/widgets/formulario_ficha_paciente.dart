import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/imagen_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/validacion_ficha_paciente.dart';
import 'snackbars.dart';

/// Campos compartidos por el alta y la edición de la ficha del paciente.
///
/// Tenerlos en un solo widget evita que las dos pantallas se desincronicen en
/// etiquetas, formateadores, límites o en el flujo de la foto.
class FormularioFichaPaciente extends StatelessWidget {
  final TextEditingController nombreController;
  final TextEditingController edadController;
  final TextEditingController condicionController;
  final TextEditingController contactoController;
  final String? fotoBase64;
  final ValueChanged<String?> onFotoCambiada;
  final bool permitirQuitarFoto;
  final bool habilitado;
  final String textoAyudaFoto;

  const FormularioFichaPaciente({
    super.key,
    required this.nombreController,
    required this.edadController,
    required this.condicionController,
    required this.contactoController,
    required this.fotoBase64,
    required this.onFotoCambiada,
    this.permitirQuitarFoto = false,
    this.habilitado = true,
    this.textoAyudaFoto = 'Toca para elegir una foto (opcional)',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: nombreController,
          enabled: habilitado,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Nombre del paciente',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 4),
        TextField(
          controller: edadController,
          enabled: habilitado,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: const InputDecoration(
            labelText: 'Edad',
            hintText: 'Ej: 78',
            helperText: 'Opcional, entre 0 y 120',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 4),
        TextField(
          controller: condicionController,
          enabled: habilitado,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(condicionMaxCaracteres),
          ],
          decoration: const InputDecoration(
            labelText: 'Condición médica',
            hintText: 'Ej: Alzheimer, Hipertensión',
            helperText: 'Opcional',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 4),
        TextField(
          controller: contactoController,
          enabled: habilitado,
          keyboardType: TextInputType.phone,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            LengthLimitingTextInputFormatter(30),
          ],
          decoration: const InputDecoration(
            labelText: 'Contacto de emergencia',
            hintText: '+34 600 000 000',
            helperText: 'Opcional, entre 7 y 15 dígitos',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 4),
        SelectorFotoPaciente(
          fotoBase64: fotoBase64,
          onFotoCambiada: onFotoCambiada,
          permitirQuitar: permitirQuitarFoto,
          habilitado: habilitado,
          textoAyuda: textoAyudaFoto,
        ),
      ],
    );
  }
}

/// Selector de foto con la misma compresión/base64 que usa el resto de la app.
///
/// La foto se guarda dentro del documento (`fotoBase64`), sin Firebase Storage.
class SelectorFotoPaciente extends StatefulWidget {
  final String? fotoBase64;
  final ValueChanged<String?> onFotoCambiada;
  final bool permitirQuitar;
  final bool habilitado;
  final String textoAyuda;
  final ImagePicker? picker;
  final ImagenService? imagenService;

  const SelectorFotoPaciente({
    super.key,
    required this.fotoBase64,
    required this.onFotoCambiada,
    this.permitirQuitar = false,
    this.habilitado = true,
    this.textoAyuda = 'Toca para elegir una foto (opcional)',
    this.picker,
    this.imagenService,
  });

  @override
  State<SelectorFotoPaciente> createState() => _SelectorFotoPacienteState();
}

class _SelectorFotoPacienteState extends State<SelectorFotoPaciente> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  late final ImagenService _imagen = widget.imagenService ?? ImagenService();
  bool _procesando = false;

  bool get _tieneFoto =>
      widget.fotoBase64 != null && widget.fotoBase64!.isNotEmpty;

  Future<void> _elegirFoto() async {
    if (!widget.habilitado || _procesando) return;
    final foto = await _picker.pickImage(source: ImageSource.gallery);
    if (foto == null || !mounted) return;
    setState(() => _procesando = true);
    try {
      final bytes = await foto.readAsBytes();
      final base64 = await _imagen.fotoABase64(bytes);
      if (!mounted) return;
      if (base64 == null) {
        mostrarSnackError(context, 'No se pudo procesar la foto. Elige otra.');
      } else {
        widget.onFotoCambiada(base64);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error foto: $e');
      }
      if (mounted) {
        mostrarSnackError(context, 'No se pudo procesar la foto. Elige otra.');
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _quitarFoto() {
    if (!widget.habilitado || _procesando) return;
    widget.onFotoCambiada(null);
  }

  @override
  Widget build(BuildContext context) {
    Widget contenido;
    if (_procesando) {
      contenido = const Center(child: CircularProgressIndicator());
    } else if (_tieneFoto) {
      final bytes = ImagenService.decodificar(widget.fotoBase64!);
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final cache = (120 * dpr).round().clamp(1, 4096).toInt();
      contenido = bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.button),
              child: Image.memory(
                bytes,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: cache,
                cacheHeight: cache,
                errorBuilder: (_, _, _) => const _IconoFotoPaciente(),
              ),
            )
          : const _IconoFotoPaciente();
    } else {
      contenido = const _IconoFotoPaciente();
    }

    return Column(
      children: [
        Semantics(
          button: widget.habilitado,
          label: _tieneFoto
              ? 'Cambiar foto del paciente'
              : 'Elegir foto del paciente',
          child: GestureDetector(
            onTap: widget.habilitado && !_procesando ? _elegirFoto : null,
            child: contenido,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.textoAyuda,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        if (widget.permitirQuitar && _tieneFoto && !_procesando)
          TextButton.icon(
            onPressed: widget.habilitado ? _quitarFoto : null,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Quitar foto'),
          ),
      ],
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
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      child: const Icon(Icons.add_a_photo, size: 36, color: AppColors.accent),
    );
  }
}
