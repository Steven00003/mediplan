import 'dart:async';

import 'package:flutter/material.dart';

/// Ejecuta [accion] con un diálogo de progreso bloqueante y garantiza que el
/// diálogo se cierre pase lo que pase.
///
/// El cierre va en `finally`: si la acción falla, el error se propaga al
/// llamador, pero el diálogo ya no queda abierto encima del mensaje de error.
Future<void> ejecutarConDialogoDeProgreso({
  required BuildContext context,
  required WidgetBuilder builder,
  required Future<void> Function() accion,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: builder,
    ),
  );

  try {
    await accion();
  } finally {
    if (navigator.mounted) navigator.pop();
  }
}
