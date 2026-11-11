import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Diálogo común para acciones delicadas.
///
/// La acción destructiva queda como texto rojo pequeño y "Cancelar" como botón
/// prominente, igual que en el flujo del paciente.
Future<bool> mostrarDialogoAccionDelicada(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String textoAccion,
  IconData icono = Icons.warning_amber_rounded,
}) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(icono, color: AppColors.error, size: AppSizes.icon),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(titulo)),
        ],
      ),
      content: Text(mensaje),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(textoAccion),
        ),
        ElevatedButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
  return confirmado ?? false;
}
