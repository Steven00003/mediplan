import '../models/estado_dispositivo.dart';

/// Cada cuánto se reescribe el estado del celular si los valores no cambiaron.
const Duration intervaloReporteEstadoDispositivo = Duration(minutes: 30);

/// Texto exacto que se muestra al cuidador cuando hay riesgo de que la alarma
/// no suene. No cambiar sin actualizar las pruebas y la tarjeta del detalle.
const String mensajeAlarmasNoSuenan =
    'Es posible que las alarmas no suenen. Pide al paciente que abra MediPlan.';

/// Decide si hay que escribir `pacientes/{id}.estadoDispositivo`.
///
/// - Un valor distinto siempre se reporta de inmediato.
/// - Si no cambió nada, se espera al menos [intervalo] desde el último envío.
bool debeReportarEstadoDispositivo({
  required DateTime ahora,
  required DateTime? ultimoEnvio,
  required String? firmaAnterior,
  required String firmaActual,
  Duration intervalo = intervaloReporteEstadoDispositivo,
}) {
  if (firmaAnterior == null || firmaAnterior != firmaActual) return true;
  if (ultimoEnvio == null) return true;
  return ahora.difference(ultimoEnvio) >= intervalo;
}

/// Texto relativo para la tarjeta del cuidador.
String textoUltimaSincronizacion(DateTime? ultima, DateTime ahora) {
  if (ultima == null) return 'sin datos';
  final diferencia = ahora.difference(ultima);
  if (diferencia.isNegative || diferencia.inMinutes < 1) {
    return 'hace un momento';
  }
  if (diferencia.inMinutes < 60) {
    return 'hace ${diferencia.inMinutes} min';
  }
  if (diferencia.inHours < 24) {
    return diferencia.inHours == 1
        ? 'hace 1 hora'
        : 'hace ${diferencia.inHours} horas';
  }
  return diferencia.inDays == 1
      ? 'hace 1 día'
      : 'hace ${diferencia.inDays} días';
}

/// Si el cuidador debe ver el aviso de alarmas en riesgo.
///
/// Un paciente vinculado sin reporte también se avisa: no se puede confirmar
/// que su celular tenga las alarmas programadas.
bool necesitaAvisoAlarmas(EstadoDispositivo? estado, DateTime ahora) {
  if (estado == null) return true;
  if (!estado.notificacionesPermitidas) return true;
  if (!estado.bateriaSinRestricciones) return true;
  final ultima = estado.ultimaSincronizacion;
  if (ultima == null) return true;
  return ahora.difference(ultima) > const Duration(hours: 24);
}
