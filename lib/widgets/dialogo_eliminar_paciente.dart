import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/confirmacion_eliminar_paciente.dart';

/// Confirmación destructiva para eliminar un paciente.
///
/// Devuelve `true` solo si el doctor escribió el nombre exacto. El botón de
/// eliminar permanece deshabilitado hasta entonces.
class DialogoEliminarPaciente extends StatefulWidget {
  final String nombrePaciente;

  const DialogoEliminarPaciente({super.key, required this.nombrePaciente});

  @override
  State<DialogoEliminarPaciente> createState() =>
      _DialogoEliminarPacienteState();
}

class _DialogoEliminarPacienteState extends State<DialogoEliminarPaciente> {
  final TextEditingController _controller = TextEditingController();

  bool get _coincide => nombreConfirmaEliminacion(
    nombrePaciente: widget.nombrePaciente,
    textoEscrito: _controller.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.delete_forever, color: AppColors.error),
      title: const Text('Eliminar paciente'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrarán el paciente, sus medicamentos y todo su historial '
              'de tomas. Esta acción no se puede deshacer.',
            ),
            const SizedBox(height: 16),
            Text(
              'Escribe "${widget.nombrePaciente}" para confirmar:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_coincide) Navigator.of(context).pop(true);
              },
              decoration: const InputDecoration(
                labelText: 'Nombre del paciente',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _coincide ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onAccent,
          ),
          child: const Text('Eliminar paciente'),
        ),
      ],
    );
  }
}
