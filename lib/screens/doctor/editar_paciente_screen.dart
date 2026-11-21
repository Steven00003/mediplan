import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/paciente.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/errores_amigables.dart';
import '../../utils/validacion_ficha_paciente.dart';
import '../../widgets/boton_cargando.dart';
import '../../widgets/dialogo_accion_delicada.dart';
import '../../widgets/formulario_ficha_paciente.dart';
import '../../widgets/snackbars.dart';

/// Edita la ficha visible del paciente: nombre, edad, condición, contacto de
/// emergencia y foto.
///
/// Nunca toca los campos de autorización o vinculación (`cuidadorId`,
/// `dispositivoVinculadoId`, `codigoVinculacion`): el detalle los sigue
/// gestionando por sus propios flujos.
class EditarPacienteScreen extends StatefulWidget {
  final Paciente paciente;

  const EditarPacienteScreen({super.key, required this.paciente});

  @override
  State<EditarPacienteScreen> createState() => _EditarPacienteScreenState();
}

class _EditarPacienteScreenState extends State<EditarPacienteScreen> {
  final FirestoreService _fs = FirestoreService();

  late final TextEditingController _nombreController;
  late final TextEditingController _edadController;
  late final TextEditingController _condicionController;
  late final TextEditingController _contactoController;
  late String? _fotoBase64;

  bool _guardando = false;
  bool _confirmandoSalida = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final paciente = widget.paciente;
    _nombreController = TextEditingController(text: paciente.nombre);
    _edadController = TextEditingController(
      text: paciente.edad?.toString() ?? '',
    );
    _condicionController = TextEditingController(
      text: paciente.condicion ?? '',
    );
    _contactoController = TextEditingController(
      text: paciente.contactoEmergencia ?? '',
    );
    _fotoBase64 = paciente.fotoBase64;

    for (final controller in _controllers) {
      controller.addListener(_alCambiarTexto);
    }
  }

  List<TextEditingController> get _controllers => [
    _nombreController,
    _edadController,
    _condicionController,
    _contactoController,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_alCambiarTexto);
      controller.dispose();
    }
    super.dispose();
  }

  void _alCambiarTexto() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  void _cambiarFoto(String? foto) {
    setState(() {
      _fotoBase64 = foto;
      _error = null;
    });
  }

  /// Compara valores normalizados para que añadir solo espacios no cuente como
  /// un cambio que merezca el diálogo de descarte.
  bool get _hayCambios {
    final paciente = widget.paciente;
    if (normalizarNombrePaciente(_nombreController.text) !=
        normalizarNombrePaciente(paciente.nombre)) {
      return true;
    }
    if (_edadController.text.trim() != (paciente.edad?.toString() ?? '')) {
      return true;
    }
    if (normalizarTextoOpcional(_condicionController.text) !=
        normalizarTextoOpcional(paciente.condicion ?? '')) {
      return true;
    }
    if (_telefonoComparable(_contactoController.text) !=
        _telefonoComparable(paciente.contactoEmergencia)) {
      return true;
    }
    if ((_fotoBase64 ?? '') != (paciente.fotoBase64 ?? '')) return true;
    return false;
  }

  String _telefonoComparable(String? texto) {
    return (texto ?? '').trim().replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> _guardar() async {
    if (_guardando) return;

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
      _guardando = true;
      _error = null;
    });

    try {
      await _fs.actualizarFichaPaciente(
        pacienteId: widget.paciente.id,
        nombre: datos.nombre,
        edad: datos.edad,
        condicion: datos.condicion,
        contactoEmergencia: datos.contactoEmergencia,
        fotoBase64: _fotoBase64,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _guardando = false);
      mostrarSnackExito(context, 'Ficha actualizada');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = mensajeErrorAmigable(e, contexto: 'Error actualizando ficha');
      });
    }
  }

  Future<void> _confirmarSalida() async {
    if (_confirmandoSalida) return;
    _confirmandoSalida = true;
    final descartar = await mostrarDialogoAccionDelicada(
      context,
      titulo: '¿Descartar cambios?',
      mensaje:
          'Si sales ahora, se perderán los cambios que hiciste en la ficha '
          'del paciente.',
      textoAccion: 'Descartar',
      icono: Icons.edit_off,
    );
    _confirmandoSalida = false;
    if (!mounted) return;
    if (descartar) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Con cambios pendientes, el atrás del sistema pregunta antes de salir.
      canPop: !_hayCambios && !_guardando,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _guardando) return;
        await _confirmarSalida();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Editar paciente', overflow: TextOverflow.ellipsis),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormularioFichaPaciente(
                nombreController: _nombreController,
                edadController: _edadController,
                condicionController: _condicionController,
                contactoController: _contactoController,
                fotoBase64: _fotoBase64,
                onFotoCambiada: _cambiarFoto,
                permitirQuitarFoto: true,
                habilitado: !_guardando,
                textoAyudaFoto: _fotoBase64 == null
                    ? 'Toca para elegir una foto (opcional)'
                    : 'Toca para cambiar la foto',
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              BotonCargando(
                cargando: _guardando,
                onPressed: _guardar,
                texto: 'Guardar cambios',
                icono: Icons.save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
