import '../models/registro_toma.dart';

/// Rótulos de texto para mostrar una toma programada en el historial.
///
/// Funciones puras a propósito — y no helpers privados de un widget — por lo
/// mismo que `resumen_horario.dart`: son reglas de formato con casos límite
/// (cruce de medianoche, año distinto) que se pueden fijar en tests sin
/// Firebase ni widgets.

/// Hora en formato corto `08:00`.
String horaCorta(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Día de una toma programada como texto corto: `Hoy`, `Ayer`, `Mié 12` o
/// `12 mar 2025` si es de otro año.
///
/// Se comparan **días de calendario**, no diferencias de 24 h: una toma de las
/// 23:50 de ayer y otra de las 00:10 de hoy están a 20 minutos una de otra pero
/// caen en días distintos, y en un historial eso es justo lo que hay que ver.
///
/// Fuera de hoy/ayer se incluye el número de día a propósito: el historial llega
/// a 50 filas y un `Mié` a secas no dice de qué miércoles se trata.
String etiquetaDia(DateTime fecha, {DateTime? ahora}) {
  final ref = ahora ?? DateTime.now();
  final hoy = DateTime(ref.year, ref.month, ref.day);
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final diff = hoy.difference(dia).inDays;

  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  if (fecha.year == ref.year) return '${_diaCorto(fecha.weekday)} ${fecha.day}';
  return '${fecha.day} ${_mesCorto(fecha.month)} ${fecha.year}';
}

/// Día y hora programada de un registro: `Hoy · 08:00`.
///
/// Se usa la hora **programada**, no la de confirmación: el historial responde
/// "¿tomó esta dosis a tiempo?", y el momento en que la confirmó se muestra
/// aparte (ver [horaConfirmacionCorta]).
String etiquetaProgramada(RegistroToma r, {DateTime? ahora}) =>
    '${etiquetaDia(r.horaProgramada, ahora: ahora)} · '
    '${horaCorta(r.horaProgramada)}';

/// Hora a la que se confirmó, o cadena vacía si nunca se confirmó.
///
/// Vacía (y no `null`) para que el llamador pueda incrustarla directamente sin
/// tener que decidir el caso "sin confirmar": en la práctica solo `olvidada`
/// llega sin confirmar, porque una toma olvidada es justamente la que nunca se
/// confirmó.
String horaConfirmacionCorta(RegistroToma r) {
  final c = r.horaConfirmacion;
  return c == null ? '' : horaCorta(c);
}

String _diaCorto(int iso) {
  const nombres = {
    1: 'Lun',
    2: 'Mar',
    3: 'Mié',
    4: 'Jue',
    5: 'Vie',
    6: 'Sáb',
    7: 'Dom',
  };
  return nombres[iso] ?? '?';
}

String _mesCorto(int mes) {
  const nombres = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return (mes >= 1 && mes <= 12) ? nombres[mes - 1] : '?';
}