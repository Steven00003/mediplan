import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Estado vacío reutilizable: ícono, título, mensaje y una acción opcional.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icono,
              size: AppSizes.iconXLarge + AppSizes.iconLarge,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            if (accion != null) ...[
              const SizedBox(height: AppSpacing.md),
              accion!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de error reutilizable. El texto debe ser amable; el detalle técnico
/// nunca se muestra aquí.
class EstadoError extends StatelessWidget {
  final String mensaje;
  final VoidCallback? onReintentar;
  final String titulo;
  final IconData icono;

  const EstadoError({
    super.key,
    required this.mensaje,
    this.onReintentar,
    this.titulo = 'No pudimos cargar esto',
    this.icono = Icons.cloud_off,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icono,
              size: AppSizes.iconXLarge + AppSizes.iconLarge,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            if (onReintentar != null) ...[
              const SizedBox(height: AppSpacing.md),
              ElevatedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de carga con un texto corto y accesible.
class EstadoCargando extends StatelessWidget {
  final String texto;

  const EstadoCargando({super.key, this.texto = 'Cargando...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: texto,
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
