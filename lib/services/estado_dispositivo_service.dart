import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../constants.dart';
import '../models/estado_dispositivo.dart';
import '../utils/reporte_estado_dispositivo.dart';
import 'firestore_service.dart';
import 'local_store.dart';
import 'notificaciones_service.dart';

/// Recolecta y publica el estado del celular del paciente.
///
/// El reporte se escribe en `pacientes/{id}.estadoDispositivo` y solo lo hace
/// el dispositivo vinculado. Es best-effort: un fallo de permisos, red o del
/// plugin no debe afectar a las alarmas ni a la navegación del paciente.
class EstadoDispositivoService {
  final NotificacionesService _notif;
  final FirestoreService _fs;

  EstadoDispositivoService({
    NotificacionesService? notificaciones,
    FirestoreService? firestore,
  }) : _notif = notificaciones ?? NotificacionesService(),
       _fs = firestore ?? FirestoreService();

  /// Reporta si corresponde según el throttle de 30 minutos.
  ///
  /// Devuelve `true` solo si esta llamada llegó a escribir en Firestore.
  Future<bool> reportar(
    String pacienteId, {
    bool forzar = false,
    DateTime? ahora,
  }) async {
    if (!await _notif.sesionPacienteActiva(pacienteEsperado: pacienteId)) {
      return false;
    }

    try {
      final estado = await _recolectar();
      final firma = estado.firma(pacienteId);
      final referencia = ahora ?? DateTime.now();

      if (!forzar) {
        final ultimo = await LocalStore.getUltimoEnvioEstadoDispositivo();
        final firmaAnterior = await LocalStore.getFirmaEstadoDispositivo();
        final debeEscribir = debeReportarEstadoDispositivo(
          ahora: referencia,
          ultimoEnvio: ultimo,
          firmaAnterior: firmaAnterior,
          firmaActual: firma,
        );
        if (!debeEscribir) return false;
      }

      await _fs.actualizarEstadoDispositivo(pacienteId, estado);
      await LocalStore.guardarEnvioEstadoDispositivo(
        fecha: referencia,
        firma: firma,
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo reportar el estado del dispositivo: $e');
      }
      return false;
    }
  }

  Future<EstadoDispositivo> _recolectar() async {
    final pendientes = await _notif.solicitudesPendientes();
    final notificaciones = await _notif.notificacionesHabilitadas();
    final energia = await _notif.estadoEnergia();
    final sdk = await _notif.androidSdkInt();
    final fabricante = await _notif.fabricanteDispositivo();

    return EstadoDispositivo(
      // La fecha real la pone Firestore con serverTimestamp().
      ultimaSincronizacion: null,
      // Se excluye la alarma de prueba del diagnóstico para no inflar el número
      // que ve el cuidador.
      alarmasProgramadas: pendientes
          .where((p) => p.id != NotificacionesService.idAlarmaPrueba)
          .length,
      // Si el plugin no puede responder, no se inventa una denegación: un
      // `desconocido` no debe disparar el aviso de "no van a sonar".
      notificacionesPermitidas: notificaciones ?? true,
      bateriaSinRestricciones:
          energia?['ignoringBatteryOptimizations'] != false,
      versionAndroid: sdk ?? 0,
      fabricante: fabricante ?? '',
      versionApp: appVersion,
    );
  }
}
