import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Convierte la foto del medicamento en una cadena base64 para guardarla dentro
/// del propio documento de Firestore (sin depender de Firebase Storage).
///
/// Para no exceder el límite de ~1 MB por documento de Firestore, la imagen se
/// redimensiona y comprime hasta caber en [maxBytes].
class ImagenService {
  static const int maxBytes = 280 * 1024; // ~280 KB
  static const int maxDimension = 800; // lado máximo de la imagen
  static const String _prefijo = 'data:image/jpeg;base64,';

  /// Recibe los bytes de la foto seleccionada y devuelve una cadena base64 (con
  /// data URI) lista para guardarse en el campo `fotoBase64` del tratamiento.
  ///
  /// Devuelve null si no se pudo procesar la imagen.
  Future<String?> fotoABase64(Uint8List bytes) async {
    try {
      img.Image? imagen = img.decodeImage(bytes);
      if (imagen == null) return null;

      // Redimensiona manteniendo la proporción para no exceder el lado máximo.
      if (imagen.width > maxDimension || imagen.height > maxDimension) {
        imagen = img.copyResize(imagen,
            width: imagen.width > imagen.height ? maxDimension : null,
            height: imagen.width > imagen.height ? null : maxDimension,
            interpolation: img.Interpolation.linear);
      }

      var calidad = 85;
      Uint8List? comprimida;
      while (calidad >= 30) {
        comprimida = Uint8List.fromList(
            img.encodeJpg(imagen, quality: calidad));
        if (comprimida.length <= maxBytes) break;
        calidad -= 15;
      }

      return '$_prefijo${base64Encode(comprimida!)}';
    } catch (e) {
      debugPrint('Error foto: $e');
      return null;
    }
  }

  /// Lado del prefijo para validar cadenas base64 almacenadas.
  static bool esBase64(String dato) => dato.startsWith(_prefijo);

  /// Obtiene los bytes decodificados desde una cadena base64 almacenada
  /// (quita el prefijo `data:` si está presente).
  static Uint8List? decodificar(String dato) {
    try {
      final limpio = dato.contains(',')
          ? dato.substring(dato.indexOf(',') + 1)
          : dato;
      return base64Decode(limpio);
    } catch (e) {
      debugPrint('Error foto: $e');
      return null;
    }
  }
}
