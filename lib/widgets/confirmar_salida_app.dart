import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Confirma el cierre COMPLETO de la app cuando se usa el gesto/botón de atrás
/// de Android estando en una pantalla que es la **raíz** de la navegación.
///
/// Hoy eso ocurre en dos pantallas, porque [HomeRouter] las devuelve como el
/// contenido de la ruta raíz (no se llega a ellas con `Navigator.push`):
///  - [SeleccionRolScreen]: nadie logueado / rol por elegir.
///  - [DashboardScreen]: cuidador con sesión recordada, que entra directo aquí
///    sin pasar por el selector de rol.
///
/// La navegación interna NO se ve afectada: `PopScope` solo intercepta mientras
/// esta pantalla es la ruta superior; si hay otra ruta empujada encima
/// (`Navigator.push`), el atrás lo resuelve esa ruta como siempre.
///
/// No confundir con el `PopScope(canPop: false)` de
/// `medicamentos_proximos_screen.dart` (rol paciente): aquel bloquea el atrás
/// por completo y responde a otra necesidad (la salida oculta por toque largo).
class ConfirmarSalidaApp extends StatelessWidget {
  const ConfirmarSalidaApp({super.key, required this.child});

  /// Contenido de la pantalla raíz (normalmente un `Scaffold`).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // No dejar cerrar de inmediato: primero se confirma.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _confirmarSalida(context);
      },
      child: child,
    );
  }

  /// Pregunta si se quiere cerrar la app y, solo si se confirma, la cierra con
  /// [SystemNavigator.pop]. Cerrar tocando fuera del diálogo (o con el atrás)
  /// equivale a cancelar.
  Future<void> _confirmarSalida(BuildContext context) async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir de MediPlan?'),
        content: const Text(
          'Se cerrará la aplicación. Podrás volver a abrirla cuando quieras.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // Cerrar la app es destructivo: nunca es la opción por defecto ni la
          // destacada; "Cancelar" va con autofocus y en color de acción.
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Salir'),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              minimumSize: const Size(140, 48),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    // null = se descartó el diálogo (toque fuera o atrás) → no se cierra.
    if (salir == true) {
      await SystemNavigator.pop();
    }
  }
}
