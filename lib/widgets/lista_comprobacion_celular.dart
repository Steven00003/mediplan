import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/comprobar_celular.dart';

/// Un punto de la lista con su estado ya calculado.
class PuntoComprobacionVista {
  final PuntoCelular punto;
  final bool listo;

  const PuntoComprobacionVista({required this.punto, required this.listo});
}

/// Lista de verificación de permisos del celular del paciente.
///
/// Es un widget aparte de la pantalla para poder probar el diseño y el estado
/// sin lanzar llamadas nativas ni leer Firestore.
class ListaComprobacionCelular extends StatelessWidget {
  final List<PuntoComprobacionVista> puntos;
  final ValueChanged<PuntoCelular> onAbrir;

  const ListaComprobacionCelular({
    super.key,
    required this.puntos,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in puntos)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _TarjetaPunto(
              key: ValueKey('punto-${item.punto.name}'),
              item: item,
              onAbrir: () => onAbrir(item.punto),
            ),
          ),
      ],
    );
  }
}

class _TarjetaPunto extends StatelessWidget {
  final PuntoComprobacionVista item;
  final VoidCallback onAbrir;

  const _TarjetaPunto({super.key, required this.item, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final listo = item.listo;
    final colorEstado = listo ? AppColors.primaryStrong : AppColors.warning;
    final iconoEstado = listo ? Icons.check_circle : Icons.error_outline;
    final textoEstado = listo ? 'Listo' : 'Pendiente';

    return Semantics(
      label: '${item.punto.titulo}: $textoEstado',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(iconoEstado, color: colorEstado, size: AppSizes.icon),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.punto.titulo,
                          style: AppType.body.copyWith(
                            color: AppColors.onGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          textoEstado,
                          style: AppType.label.copyWith(color: colorEstado),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.punto.descripcion,
                style: AppType.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAbrir,
                  icon: const Icon(Icons.open_in_new, size: AppSizes.iconSmall),
                  label: Text(item.punto.etiquetaBoton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
