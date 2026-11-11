import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Traduce un error de Firebase o de red a un mensaje que el usuario pueda
/// entender. El detalle técnico se queda únicamente en el log de depuración.
String mensajeErrorAmigable(Object error, {String? contexto}) {
  if (kDebugMode) {
    debugPrint('${contexto ?? 'Error'}: $error');
  }

  return switch (_codigo(error)) {
    'network-request-failed' || 'unavailable' =>
      'Parece que no tienes conexión. Revisa tu internet e inténtalo de nuevo.',
    'permission-denied' =>
      'No tienes permiso para hacer eso. Vuelve a iniciar sesión o pide ayuda.',
    'unauthenticated' => 'Tu sesión expiró. Vuelve a iniciar sesión.',
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => 'El correo o la contraseña no son correctos. Revísalos e inténtalo de nuevo.',
    'email-already-in-use' => 'Ese correo ya está registrado. Inicia sesión.',
    'weak-password' =>
      'La contraseña es demasiado corta. Usa al menos 6 caracteres.',
    'missing-password' => 'Escribe tu contraseña.',
    'too-many-requests' || 'resource-exhausted' =>
      'Hiciste demasiados intentos. Espera un momento y vuelve a intentarlo.',
    'user-disabled' => 'Esta cuenta está deshabilitada. Contacta a soporte.',
    'operation-not-allowed' => 'Este método de acceso no está habilitado.',
    'account-exists-with-different-credential' =>
      'Ese correo ya está asociado a otro método de acceso.',
    'requires-recent-login' =>
      'Por seguridad, vuelve a iniciar sesión antes de continuar.',
    'failed-precondition' =>
      'Falta un paso para completar la acción. Inténtalo de nuevo.',
    'not-found' => 'No se encontró esa información. Puede que ya no exista.',
    'already-exists' => 'Esa información ya existe.',
    'deadline-exceeded' => 'La operación tardó demasiado. Inténtalo de nuevo.',
    'cancelled' => 'La operación se canceló.',
    'invalid-argument' =>
      'Los datos no son válidos. Revísalos e inténtalo de nuevo.',
    _ => 'No se pudo completar la acción. Revisa tu conexión e inténtalo de nuevo.',
  };
}

String _codigo(Object error) {
  if (error is FirebaseAuthException) return error.code;
  if (error is FirebaseException) return error.code;
  return '';
}
