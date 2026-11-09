import 'package:flutter/material.dart';

/// Única fuente de verdad de la paleta de MediPlan.
///
/// Ningún widget debe escribir un `Color(0x...)` literal: se usan estos roles
/// (directamente o heredando el `ThemeData` de [buildAppTheme], en
/// `lib/theme/app_theme.dart`), así un cambio de diseño se hace en un solo
/// lugar.
///
/// Reparto de roles:
///  - [primary]  verde claro → botones secundarios, fondos de tarjeta, appBar.
///  - [accent]   verde medio → acciones principales (CTA).
///  - [onGreen]  texto/íconos oscuros que van **sobre** verde claro.
///  - [background] gris muy claro → fondo de pantalla.
///  - [textSecondary] gris → texto de apoyo, subtítulos, hints.
///  - [border]   gris muy claro → separadores y contornos de campo.
class AppColors {
  AppColors._();

  /// Verde claro. Botones secundarios, fondos de tarjeta y appBar.
  static const Color primary = Color(0xFFA8E6B0);

  /// Verde de acción: CTAs ("Generar código", "Unirme", "YA", FAB).
  static const Color accent = Color(0xFF4CAF50);

  /// Verde oscuro para la tarjeta principal de reingreso. Es lo bastante
  /// oscuro para que el texto blanco cumpla contraste AA.
  static const Color primaryStrong = Color(0xFF2E7D32);

  /// Texto/íconos oscuros sobre verde claro o sobre tarjeta blanca.
  static const Color onGreen = Color(0xFF1B3A21);

  /// Fondo general de las pantallas.
  static const Color background = Color(0xFFF8F9FA);

  /// Texto secundario: subtítulos, descripciones, texts de apoyo.
  static const Color textSecondary = Color(0xFF6B7280);

  /// Bordes de campos, `Divider`s y contornos sutiles.
  static const Color border = Color(0xFFE0E0E0);

  /// Tarjetas y contenedores sobre [background].
  static const Color surface = Colors.white;

  /// Texto sobre [accent] (botón de acción principal).
  static const Color onAccent = Colors.white;

  /// Estados. NO son colores de marca: se mantienen fuera de la paleta verde a
  /// propósito, para que un error o un aviso sigan leyéndose como tales.
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFEF6C00);

  /// Ámbar: el tono intermedio entre [accent] y [warning], para lo que sí se
  /// resolvió pero fuera de hora (una toma tardía). [warning] queda para el
  /// aviso en sí, como una toma pospuesta.
  static const Color amber = Color(0xFFF9A825);

  /// `ColorScheme` derivado de la paleta, para que los widgets que lo consulten
  /// (y los que hoy usan `Colors.*` por descuido) hereden los mismos tonos.
  static ColorScheme get colorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: primary,
      onPrimary: onGreen,
      primaryContainer: primary,
      onPrimaryContainer: onGreen,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: primary,
      onSecondaryContainer: onGreen,
      surface: surface,
      onSurface: onGreen,
      error: error,
      onError: onAccent,
      outline: border,
      outlineVariant: border,
    );
  }
}
