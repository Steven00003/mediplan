import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo de MediPlan: el badge circular (reloj + cápsula) de
/// `assets/icon/icon.png`, con fondo transparente, y el nombre "MediPlan" en
/// negrita debajo.
///
/// La imagen ya viene recortada y sin fondo, así que se muestra directamente
/// sobre el fondo de la pantalla (verde `AppColors.primary`), sin ningún
/// contenedor ni círculo blanco detrás. Es el mismo archivo que usa el launcher
/// (adaptive icon) y el splash nativo.
///
/// Se usa en el splash (`BootstrapScreen`) y en la pantalla de selección de rol.
class AppLogo extends StatelessWidget {
  /// Lado del badge del logo (la imagen es cuadrada y el círculo va centrado).
  final double tamanoLogo;

  /// Tamaño de la tipografía del nombre.
  final double tamanoTexto;

  const AppLogo({
    super.key,
    this.tamanoLogo = 120,
    this.tamanoTexto = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icon/icon.png',
          width: tamanoLogo,
          height: tamanoLogo,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        Text(
          'MediPlan',
          style: TextStyle(
            color: AppColors.onGreen,
            fontSize: tamanoTexto,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}