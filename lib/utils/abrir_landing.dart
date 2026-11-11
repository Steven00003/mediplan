import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../widgets/snackbars.dart';

/// Abre la landing del proyecto en el navegador externo.
///
/// Es el mismo mecanismo que usa el logo de la pantalla de selección de rol:
/// navegador externo y, si no se puede abrir, un mensaje amable sin romper el
/// flujo.
Future<void> abrirLanding(BuildContext context) async {
  var abierto = false;
  try {
    abierto = await launchUrl(
      Uri.parse(urlLanding),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Error abriendo la landing: $e');
    }
    abierto = false;
  }

  if (!abierto && context.mounted) {
    mostrarSnackError(
      context,
      'No pudimos abrir la página. Revisa tu conexión e inténtalo de nuevo.',
    );
  }
}
