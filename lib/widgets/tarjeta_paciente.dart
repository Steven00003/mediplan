import 'package:flutter/material.dart';

import '../models/paciente.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'avatar_paciente.dart';

/// Chip compacto para la condición médica del paciente.
class ChipCondicion extends StatelessWidget {
  final String texto;

  const ChipCondicion({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.label.copyWith(color: AppColors.onGreen, fontSize: 12),
      ),
    );
  }
}

/// Tarjeta de un paciente en la lista del cuidador.
///
/// No consulta Firestore: todo lo que muestra viene del documento `paciente`.
class TarjetaPaciente extends StatelessWidget {
  final Paciente paciente;
  final VoidCallback onTap;

  const TarjetaPaciente({
    super.key,
    required this.paciente,
    required this.onTap,
  });

  bool get _vinculado =>
      paciente.dispositivoVinculadoId != null &&
      paciente.dispositivoVinculadoId!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final edad = paciente.edad;
    final condicion = paciente.condicion?.trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarPaciente(paciente: paciente),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paciente.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.button.copyWith(color: AppColors.onGreen),
                    ),
                    if (edad != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$edad ${edad == 1 ? 'año' : 'años'}',
                        style: AppType.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (condicion != null && condicion.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ChipCondicion(texto: condicion),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    _BadgeVinculo(vinculado: _vinculado),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeVinculo extends StatelessWidget {
  final bool vinculado;

  const _BadgeVinculo({required this.vinculado});

  @override
  Widget build(BuildContext context) {
    final color = vinculado ? AppColors.primaryStrong : AppColors.warning;
    final texto = vinculado ? 'Vinculado' : 'Sin vincular';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(
                color: AppColors.onGreen,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
