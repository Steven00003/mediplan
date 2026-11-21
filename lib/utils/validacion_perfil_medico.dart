/// Reglas puras del perfil del doctor que ve el paciente.
library;

import 'dart:convert';
import 'dart:typed_data';

const int maxNombreMedico = 80;
const int maxTituloMedico = 120;
const int maxEspecialidadMedico = 80;
const int maxFotoPerfilBytes = 60 * 1024;

/// Devuelve los errores por campo, o un mapa vacío si el perfil es válido.
Map<String, String> validarPerfilMedico({
  required String nombre,
  required String titulo,
  required String especialidad,
  String? fotoBase64,
}) {
  final errores = <String, String>{};
  final n = nombre.trim();
  final t = titulo.trim();
  final e = especialidad.trim();

  if (n.isEmpty) {
    errores['nombre'] = 'Escribe tu nombre.';
  } else if (n.length > maxNombreMedico) {
    errores['nombre'] = 'El nombre no puede superar los 80 caracteres.';
  }
  if (t.length > maxTituloMedico) {
    errores['titulo'] = 'Los estudios no pueden superar los 120 caracteres.';
  }
  if (e.length > maxEspecialidadMedico) {
    errores['especialidad'] =
        'La especialidad no puede superar los 80 caracteres.';
  }

  if (fotoBase64 != null && fotoBase64.isNotEmpty) {
    final bytes = _bytesDeDataUri(fotoBase64);
    if (bytes == null) {
      errores['fotoBase64'] = 'La foto no es válida.';
    } else if (bytes.length > maxFotoPerfilBytes) {
      errores['fotoBase64'] = 'La foto debe pesar menos de 60 KB.';
    }
  }
  return errores;
}

bool esPerfilMedicoValido({
  required String nombre,
  required String titulo,
  required String especialidad,
  String? fotoBase64,
}) {
  return validarPerfilMedico(
    nombre: nombre,
    titulo: titulo,
    especialidad: especialidad,
    fotoBase64: fotoBase64,
  ).isEmpty;
}

Uint8List? _bytesDeDataUri(String dato) {
  try {
    final indice = dato.indexOf(',');
    if (indice < 0) return null;
    return base64Decode(dato.substring(indice + 1));
  } catch (_) {
    return null;
  }
}
