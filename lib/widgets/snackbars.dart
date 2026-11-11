import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

enum _TipoSnack { exito, error, info }

/// Muestra un mensaje breve de éxito con ícono.
void mostrarSnackExito(BuildContext context, String mensaje) {
  _mostrar(context, mensaje, _TipoSnack.exito);
}

/// Muestra un mensaje breve de error con ícono.
void mostrarSnackError(BuildContext context, String mensaje) {
  _mostrar(context, mensaje, _TipoSnack.error);
}

/// Muestra un mensaje breve informativo con ícono.
void mostrarSnackInfo(BuildContext context, String mensaje) {
  _mostrar(context, mensaje, _TipoSnack.info);
}

void _mostrar(BuildContext context, String mensaje, _TipoSnack tipo) {
  final (icono, fondo) = switch (tipo) {
    _TipoSnack.exito => (Icons.check_circle_outline, AppColors.primaryStrong),
    _TipoSnack.error => (Icons.error_outline, AppColors.error),
    _TipoSnack.info => (Icons.info_outline, AppColors.onGreen),
  };

  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: fondo,
        content: Row(
          children: [
            Icon(icono, color: AppColors.onAccent, size: AppSizes.icon),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                mensaje,
                style: AppType.body.copyWith(color: AppColors.onAccent),
              ),
            ),
          ],
        ),
      ),
    );
}
