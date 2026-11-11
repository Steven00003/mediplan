import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/abrir_landing.dart';
import 'acerca_de.dart';

/// Botón de ayuda reutilizable para la barra del doctor y la selección de rol.
class AyudaBoton extends StatelessWidget {
  final Color? color;

  const AyudaBoton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ayuda y acerca de',
      excludeSemantics: true,
      child: IconButton(
        icon: Icon(Icons.help_outline, color: color ?? AppColors.onGreen),
        tooltip: 'Ayuda y acerca de',
        onPressed: () => mostrarMenuAyuda(context),
      ),
    );
  }
}

/// Menú con las dos opciones de ayuda de la app.
Future<void> mostrarMenuAyuda(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'Ayuda y acerca de',
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.menu_book_outlined,
              color: AppColors.primaryStrong,
            ),
            title: const Text('Manual de uso'),
            subtitle: const Text('Abre la página del proyecto'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await abrirLanding(context);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.info_outline,
              color: AppColors.primaryStrong,
            ),
            title: const Text('Acerca de'),
            subtitle: const Text('Versión, créditos y aviso médico'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await mostrarAcercaDe(context);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    ),
  );
}
