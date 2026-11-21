import 'package:flutter/material.dart';

import '../screens/paciente/comprobar_celular_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_page_route.dart';
import '../theme/app_tokens.dart';
import '../utils/abrir_landing.dart';
import 'acerca_de.dart';

/// Botón de ayuda reutilizable para la barra del doctor y la selección de rol.
class AyudaBoton extends StatelessWidget {
  final Color? color;

  /// En el flujo del paciente añade "Comprobar mi celular" al menú.
  final bool esPaciente;

  const AyudaBoton({super.key, this.color, this.esPaciente = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ayuda y acerca de',
      excludeSemantics: true,
      child: IconButton(
        icon: Icon(Icons.help_outline, color: color ?? AppColors.onGreen),
        tooltip: 'Ayuda y acerca de',
        onPressed: () => mostrarMenuAyuda(context, esPaciente: esPaciente),
      ),
    );
  }
}

/// Menú con las opciones de ayuda de la app.
///
/// [esPaciente] añade el acceso a la revisión de permisos, guía por marca y
/// prueba de alarma del celular del paciente.
Future<void> mostrarMenuAyuda(BuildContext context, {bool esPaciente = false}) {
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
          if (esPaciente)
            ListTile(
              leading: const Icon(
                Icons.phone_android,
                color: AppColors.primaryStrong,
              ),
              title: const Text('Comprobar mi celular'),
              subtitle: const Text(
                'Permisos, guía por marca y prueba de alarma',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                if (!context.mounted) return;
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const ComprobarCelularScreen()),
                );
              },
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
