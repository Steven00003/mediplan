import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/snackbars.dart';
import 'telefono_emergencia.dart';

/// Abre el marcador del teléfono con el número ya normalizado.
///
/// Usa el mismo mecanismo que [abrirLanding]: `launchUrl` y, si el sistema no
/// puede abrirlo, un aviso amable. No llama a `canLaunchUrl`: el permiso de
/// visibilidad de Android 11 se declara en el `<queries>` del manifest y la
/// apertura se intenta directamente.
Future<void> abrirMarcadorTelefono(
  BuildContext context,
  String telefono,
) async {
  final numero = normalizarTelefonoEmergencia(telefono);
  if (numero == null) return;

  var abierto = false;
  try {
    abierto = await launchUrl(
      Uri.parse('tel:$numero'),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('Error abriendo el marcador: $e');
    abierto = false;
  }

  if (!abierto && context.mounted) {
    mostrarSnackError(
      context,
      'No pudimos abrir el marcador. El número es $numero.',
    );
  }
}
