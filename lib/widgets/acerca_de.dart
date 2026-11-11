import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Diálogo "Acerca de": nombre, versión, crédito académico y aviso médico.
Future<void> mostrarAcercaDe(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Acerca de MediPlan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/icon/icon.png',
                  width: 56,
                  height: 56,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.medication,
                    size: 56,
                    color: AppColors.primaryStrong,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'MediPlan',
                    style: AppType.title.copyWith(color: AppColors.onGreen),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Versión $appVersion',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Proyecto académico UTS · © ${DateTime.now().year}',
              style: AppType.body.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'MediPlan no es un dispositivo médico y no reemplaza la '
              'indicación de un médico.',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
