import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialogo_accion_delicada.dart';

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
    final salir = await mostrarDialogoAccionDelicada(
      context,
      titulo: '¿Salir de MediPlan?',
      mensaje:
          'Se cerrará la aplicación. Podrás volver a abrirla cuando quieras.',
      textoAccion: 'Salir',
      icono: Icons.logout,
    );
    // false = se descartó el diálogo (toque fuera o atrás) → no se cierra.
    if (salir) {
      HapticFeedback.lightImpact();
      await SystemNavigator.pop();
    }
  }
}
