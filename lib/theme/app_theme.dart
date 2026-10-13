import 'package:flutter/material.dart';

import 'app_colors.dart';

/// `ThemeData` de la app: define UNA vez colores de botones, appBar, campos,
/// tarjetas y snackbars para que las pantallas los hereden sin tener que
/// hardcodear nada.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: AppColors.colorScheme,
  );

  final borde = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onGreen,
      elevation: 0,
      centerTitle: false,
    ),

    // Acción principal: verde accent con texto blanco.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        elevation: 0,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),

    // Acción secundaria: verde claro con texto e ícono oscuros (el blanco sobre
    // `#A8E6B0` no alcanzaría contraste).
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onGreen,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: AppColors.accent, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
    ),

    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: borde,
      enabledBorder: borde,
      focusedBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      errorBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      prefixIconColor: AppColors.textSecondary,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      helperStyle: const TextStyle(color: AppColors.textSecondary),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.onGreen,
      contentTextStyle: const TextStyle(color: AppColors.onAccent),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    textTheme: base.textTheme.apply(
      bodyColor: AppColors.onGreen,
      displayColor: AppColors.onGreen,
    ).copyWith(
      // Tipografía grande y clara para el rol paciente. (Ningún widget consume
      // este slot hoy; se deja alineado al fondo claro para que, si alguien lo
      // usa, no quede texto blanco sobre verde claro.)
      displayLarge: const TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        color: AppColors.onGreen,
      ),
      titleMedium: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.onGreen,
      ),
      bodyMedium: const TextStyle(
        fontSize: 16,
        color: AppColors.onGreen,
      ),
      bodySmall: const TextStyle(
        fontSize: 14,
        color: AppColors.textSecondary,
      ),
    ),
  );
}
