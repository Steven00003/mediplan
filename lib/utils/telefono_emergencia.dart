/// Normaliza un teléfono para el marcador del sistema.
///
/// Deja solo dígitos y, si el texto original empieza por `+`, conserva ese
/// signo inicial. Acepta espacios, guiones y otros separadores habituales, pero
/// exige entre 7 y 15 dígitos para que el enlace `tel:` sea utilizable.
///
/// Devuelve `null` cuando no hay ningún dígito o la longitud no es válida.
String? normalizarTelefonoEmergencia(String? texto) {
  if (texto == null) return null;

  final recortado = texto.trim();
  if (recortado.isEmpty) return null;

  final digitos = recortado.replaceAll(RegExp(r'\D'), '');
  if (digitos.isEmpty) return null;
  if (digitos.length < 7 || digitos.length > 15) return null;

  final prefijo = recortado.startsWith('+') ? '+' : '';
  return '$prefijo$digitos';
}
