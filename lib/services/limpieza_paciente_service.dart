import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'local_store.dart';
import 'notificaciones_service.dart';
import 'push_service.dart';

/// Limpieza local común para cuando este teléfono deja de ser paciente.
///
/// La comparten `AppState` (señal del listener de Firestore) y el isolate de
/// FCM (mensaje de sincronización con el paciente ya eliminado). No gestiona
/// memoria de `AppState` ni timers: eso sigue siendo responsabilidad de quien
/// llama. Las funciones de notificaciones y push son las existentes.
class LimpiezaPacienteService {
  final NotificacionesService _notif = NotificacionesService();
  final PushService _push = PushService();

  Future<void> olvidarPaciente({
    String? pacienteId,
    bool borrarRecordada = true,
    bool cerrarSesionAnonima = true,
    String? mensajeSeleccionRol,
  }) async {
    // Debe ejecutarse antes de limpiar el flag local: el push usa el UID que
    // todavía está vinculado. Es best-effort y nunca lanza.
    unawaited(_push.cerrarSesionPaciente(pacienteId: pacienteId));

    // También antes de limpiar `paciente_id`: cancelarTodas comprueba que este
    // teléfono siga siendo una sesión de paciente activa. Un fallo del plugin
    // no debe impedir limpiar la vinculación local.
    try {
      await _notif.cancelarTodas();
    } catch (_) {
      // Las notificaciones locales se pueden volver a cancelar en el próximo
      // arranque; la prioridad aquí es no dejar el perfil vinculado.
    }
    await LocalStore.limpiarPacienteVinculado();
    if (borrarRecordada) {
      await LocalStore.limpiarUltimaVinculacion();
    }
    if (mensajeSeleccionRol != null && mensajeSeleccionRol.trim().isNotEmpty) {
      await LocalStore.guardarMensajeSeleccionRol(mensajeSeleccionRol);
    }
    if (cerrarSesionAnonima) {
      final usuario = FirebaseAuth.instance.currentUser;
      if (usuario != null && usuario.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }
    }
  }
}
