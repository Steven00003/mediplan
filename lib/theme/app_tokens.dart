import 'package:flutter/material.dart';

/// Tokens de espaciado. Todos son múltiplos de 8 para mantener un ritmo visual
/// uniforme en toda la app.
class AppSpacing {
  AppSpacing._();

  static const double xs = 8;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 40;
  static const double xxl = 48;
  static const double huge = 64;
}

/// Radios de la interfaz. No son espaciado: pueden no ser múltiplos de 8.
class AppRadii {
  AppRadii._();

  static const double button = 16;
  static const double field = 14;
  static const double card = 20;
  static const double dialog = 24;
  static const double pill = 999;
}

/// Elevaciones Material 3 usadas por la app.
class AppElevations {
  AppElevations._();

  static const double none = 0;
  static const double low = 1;
  static const double medium = 3;
  static const double high = 6;
}

/// Escala tipográfica única de MediPlan.
///
/// No fija familia: se hereda la fuente del sistema (sin Google Fonts ni CDN).
class AppType {
  AppType._();

  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    height: 1.2,
  );

  static const TextStyle title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.25,
  );

  static const TextStyle body = TextStyle(fontSize: 16, height: 1.4);

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// Medidas de componentes y accesibilidad.
class AppSizes {
  AppSizes._();

  static const double minTouch = 48;
  static const double button = 56;
  static const double appBar = 64;

  static const double iconSmall = 20;
  static const double icon = 24;
  static const double iconLarge = 32;
  static const double iconXLarge = 48;
  static const double avatar = 56;
}

/// Duraciones de movimiento compartidas por rutas y transiciones.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 220);
  static const Duration fade = Duration(milliseconds: 300);
}
