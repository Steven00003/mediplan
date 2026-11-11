import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Botón primario con estado de carga. Se deshabilita y muestra un indicador
/// mientras la operación está en curso para evitar dobles envíos.
class BotonCargando extends StatelessWidget {
  final bool cargando;
  final VoidCallback? onPressed;
  final String texto;
  final IconData? icono;
  final bool expandido;

  const BotonCargando({
    super.key,
    required this.cargando,
    required this.onPressed,
    required this.texto,
    this.icono,
    this.expandido = true,
  });

  @override
  Widget build(BuildContext context) {
    final boton = ElevatedButton(
      onPressed: cargando ? null : onPressed,
      child: cargando
          ? const SizedBox(
              width: AppSizes.icon,
              height: AppSizes.icon,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icono != null) ...[
                  Icon(icono),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(child: Text(texto, textAlign: TextAlign.center)),
              ],
            ),
    );

    if (!expandido) return boton;
    return SizedBox(width: double.infinity, child: boton);
  }
}
