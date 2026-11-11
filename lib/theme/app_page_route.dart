import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Ruta de página común: fundido con un desplazamiento vertical mínimo.
///
/// Se usa en todas las navegaciones normales para que el cambio de pantalla se
/// sienta igual en los dos flujos. Las rutas de alarma quedan fuera a propósito:
/// su presentación forma parte del comportamiento de la alarma.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: AppMotion.page,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curva = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final desplazamiento = Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curva);
          return FadeTransition(
            opacity: curva,
            child: SlideTransition(position: desplazamiento, child: child),
          );
        },
      );
}
