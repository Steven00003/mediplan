import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// `ThemeData` de la app: define UNA vez colores, espaciado, radios, elevaciones
/// y tipografía para que las pantallas los hereden sin hardcodear nada.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: AppColors.colorScheme,
  );

  final bordeCampo = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.field),
    borderSide: const BorderSide(color: AppColors.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,

    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onGreen,
      elevation: AppElevations.none,
      centerTitle: false,
      toolbarHeight: AppSizes.appBar,
      titleTextStyle: AppType.title.copyWith(color: AppColors.onGreen),
    ),

    // Acción principal: verde oscuro con texto blanco para cumplir AA.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryStrong,
        foregroundColor: AppColors.onAccent,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textSecondary,
        elevation: AppElevations.none,
        minimumSize: const Size(0, AppSizes.button),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        textStyle: AppType.button,
      ),
    ),

    // Acción secundaria: superficie clara con borde visible.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onGreen,
        minimumSize: const Size(0, AppSizes.button),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        side: const BorderSide(color: AppColors.accent, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        textStyle: AppType.button,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryStrong,
        minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        textStyle: AppType.label,
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryStrong,
      foregroundColor: AppColors.onAccent,
      elevation: AppElevations.medium,
    ),

    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: AppElevations.none,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
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
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      border: bordeCampo,
      enabledBorder: bordeCampo,
      focusedBorder: bordeCampo.copyWith(
        borderSide: const BorderSide(color: AppColors.primaryStrong, width: 2),
      ),
      errorBorder: bordeCampo.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: bordeCampo.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      prefixIconColor: AppColors.textSecondary,
      suffixIconColor: AppColors.textSecondary,
      labelStyle: AppType.body.copyWith(color: AppColors.textSecondary),
      floatingLabelStyle: AppType.label.copyWith(
        color: AppColors.primaryStrong,
      ),
      hintStyle: AppType.body.copyWith(color: AppColors.textSecondary),
      helperStyle: AppType.label.copyWith(color: AppColors.textSecondary),
      errorStyle: AppType.label.copyWith(color: AppColors.error),
      errorMaxLines: 2,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.onGreen,
      contentTextStyle: AppType.body.copyWith(color: AppColors.onAccent),
      actionTextColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      elevation: AppElevations.medium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevations.high,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
      titleTextStyle: AppType.title.copyWith(color: AppColors.onGreen),
      contentTextStyle: AppType.body.copyWith(color: AppColors.onGreen),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primaryStrong,
      unselectedItemColor: AppColors.textSecondary,
      elevation: AppElevations.none,
      type: BottomNavigationBarType.fixed,
      selectedIconTheme: const IconThemeData(
        size: AppSizes.iconLarge,
        color: AppColors.primaryStrong,
      ),
      unselectedIconTheme: const IconThemeData(
        size: AppSizes.iconLarge,
        color: AppColors.textSecondary,
      ),
      selectedLabelStyle: AppType.label.copyWith(
        color: AppColors.primaryStrong,
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: AppType.label.copyWith(
        color: AppColors.textSecondary,
      ),
    ),

    textTheme: base.textTheme
        .apply(bodyColor: AppColors.onGreen, displayColor: AppColors.onGreen)
        .copyWith(
          displayLarge: AppType.display.copyWith(color: AppColors.onGreen),
          headlineMedium: AppType.display.copyWith(color: AppColors.onGreen),
          titleLarge: AppType.title.copyWith(color: AppColors.onGreen),
          bodyLarge: AppType.body.copyWith(color: AppColors.onGreen),
          bodyMedium: AppType.body.copyWith(color: AppColors.onGreen),
          bodySmall: AppType.label.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
          ),
          labelLarge: AppType.label.copyWith(color: AppColors.onGreen),
          labelMedium: AppType.label.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
  );
}
