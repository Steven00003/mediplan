import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/conexion_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Informa al [ConexionService] sin notificar durante el build actual.
///
/// Los builders de Firestore reciben la instantánea durante `build`; si el
/// servicio notificara en ese momento, el banner intentaría reconstruirse en
/// medio de otro build. El post-frame deja la notificación para el siguiente
/// fotograma, sin tocar la lógica de datos ni las lecturas.
void reportarConexionDesde(BuildContext context, bool desdeCache) {
  final conexion = context.read<ConexionService>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) conexion.reportar(desdeCache);
  });
}

/// Aviso discreto que aparece cuando las streams llevan un rato en caché.
///
/// Es una región activa para lectores de pantalla (`liveRegion`) y se pliega
/// con animación para no dejar un hueco cuando vuelve la conexión.
class BannerSinConexion extends StatelessWidget {
  final String mensaje;

  const BannerSinConexion({super.key, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final conexion = context.watch<ConexionService>();

    return AnimatedSize(
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: conexion.sinConexion
          ? Semantics(
              liveRegion: true,
              container: true,
              label: mensaje,
              excludeSemantics: true,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.warning.withValues(alpha: 0.40),
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      size: AppSizes.iconSmall,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        mensaje,
                        style: AppType.label.copyWith(color: AppColors.onGreen),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
