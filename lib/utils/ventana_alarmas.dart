import '../models/tratamiento.dart';
import 'hash_estable.dart';

/// Una alarma puntual de una toma concreta dentro de la ventana móvil.
class OcurrenciaAlarma {
  final String tratamientoId;
  final DateTime horaProgramada;
  final String hora;

  const OcurrenciaAlarma({
    required this.tratamientoId,
    required this.horaProgramada,
    required this.hora,
  });

  int get id => VentanaAlarmas.idDeOcurrencia(tratamientoId, horaProgramada);
}

/// Cálculos puros de la ventana móvil de alarmas puntuales.
///
/// La alarma principal ya no se programa como una notificación semanal
/// recurrente: cada ocurrencia de los próximos [diasVentana] días se agenda por
/// separado con `AndroidScheduleMode.alarmClock` y sin
/// `matchDateTimeComponents`. Así cada alarma es una alarma de reloj real
/// (`setAlarmClock`) y no depende de que el receptor del plugin rearme la
/// siguiente repetición.
///
/// La ventana incluye el día de [ahora] y los [diasVentana] - 1 días
/// siguientes. Las ocurrencias de hoy que ya pasaron se omiten al programar,
/// pero se pueden incluir al calcular cancelaciones.
class VentanaAlarmas {
  const VentanaAlarmas._();

  /// Días de calendario que cubre la ventana móvil.
  static const int diasVentana = 7;

  /// Rango de ids reservado para las alarmas puntuales.
  ///
  /// Es un subrango negativo propio, contiguo al del recordatorio tardío
  /// puntual y sin solaparse con ningún otro:
  ///
  ///   aviso previo:                [-0x0FFFFFFF, -1]
  ///   felicitación:                [-0x1FFFFFFF, -0x10000000]
  ///   tardío recurrente:           [-0x27FFFFFF, -0x20000000]
  ///   tardío puntual (posponer):   [-0x2FFFFFFF, -0x28000000]
  ///   alarma puntual (ventana):    [-0x3FFFFFFF, -0x30000000]
  static const int minIdAlarmaPuntual = -0x3FFFFFFF;
  static const int maxIdAlarmaPuntual = -0x30000000;
  static const int _baseIdAlarmaPuntual = 0x30000000;
  static const int _tamanoIdAlarmaPuntual = 0x10000000;

  /// Genera las ocurrencias de [horarios] dentro de la ventana.
  ///
  /// [ahora] define el inicio de la ventana y el instante a partir del cual una
  /// ocurrencia es futura. [fechaInicio] y [duracionDias] aplican la misma
  /// vigencia inclusiva que `VigenciaTratamiento`: si hay fecha de inicio, no
  /// se generan ocurrencias anteriores a ella; si además hay duración, no se
  /// generan posteriores al último día.
  ///
  /// Con [respetarVigencia] en `false` se generan también las ocurrencias fuera
  /// de vigencia. Se usa para cancelar alarmas viejas de un tratamiento editado
  /// o terminado, cuyos parámetros de vigencia pueden haber cambiado.
  ///
  /// Las ocurrencias se devuelven ordenadas por hora y sin duplicados. Dos
  /// horarios que coincidan en el mismo día y hora producen una sola alarma
  /// porque su id también coincide.
  static List<OcurrenciaAlarma> ocurrencias({
    required String tratamientoId,
    required List<HorarioDia> horarios,
    required DateTime ahora,
    DateTime? fechaInicio,
    int? duracionDias,
    int dias = diasVentana,
    bool respetarVigencia = true,
  }) {
    if (dias <= 0 || horarios.isEmpty) return const [];

    final inicio = fechaInicio == null
        ? null
        : DateTime(fechaInicio.year, fechaInicio.month, fechaInicio.day);
    final fin = (inicio != null && duracionDias != null)
        ? DateTime(inicio.year, inicio.month, inicio.day + duracionDias - 1)
        : null;

    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final resultado = <OcurrenciaAlarma>[];
    final idsVistos = <int>{};

    for (var i = 0; i < dias; i++) {
      final dia = DateTime(hoy.year, hoy.month, hoy.day + i);
      if (respetarVigencia) {
        if (inicio != null && dia.isBefore(inicio)) continue;
        if (fin != null && dia.isAfter(fin)) continue;
      }

      for (final horario in horarios) {
        if (!horario.dias.contains(dia.weekday)) continue;
        final partes = horario.hora.split(':');
        if (partes.length != 2) continue;
        final h = int.tryParse(partes[0]);
        final m = int.tryParse(partes[1]);
        if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
          continue;
        }

        final cuando = DateTime(dia.year, dia.month, dia.day, h, m);
        if (!cuando.isAfter(ahora)) continue;
        final id = idDeOcurrencia(tratamientoId, cuando);
        if (!idsVistos.add(id)) continue;
        resultado.add(
          OcurrenciaAlarma(
            tratamientoId: tratamientoId,
            horaProgramada: cuando,
            hora:
                '${h.toString().padLeft(2, '0')}:'
                '${m.toString().padLeft(2, '0')}',
          ),
        );
      }
    }

    resultado.sort((a, b) => a.horaProgramada.compareTo(b.horaProgramada));
    return resultado;
  }

  /// Ocurrencias entre [desde] y [hasta], incluidas las ya pasadas.
  ///
  /// Se usa para reconstruir la hora de una alarma puntual que Android tiene
  /// pendiente pero cuyo metadato local ya no está. A diferencia de
  /// [ocurrencias], no exige que la ocurrencia sea futura.
  static List<OcurrenciaAlarma> ocurrenciasEnRango({
    required String tratamientoId,
    required List<HorarioDia> horarios,
    required DateTime desde,
    required DateTime hasta,
    DateTime? fechaInicio,
    int? duracionDias,
    bool respetarVigencia = true,
  }) {
    if (hasta.isBefore(desde)) return const [];
    final primerDia = DateTime(desde.year, desde.month, desde.day);
    final ultimoDia = DateTime(hasta.year, hasta.month, hasta.day);
    final dias = ultimoDia.difference(primerDia).inDays + 1;
    return ocurrencias(
      tratamientoId: tratamientoId,
      horarios: horarios,
      ahora: desde.subtract(const Duration(microseconds: 1)),
      fechaInicio: fechaInicio,
      duracionDias: duracionDias,
      dias: dias,
      respetarVigencia: respetarVigencia,
    ).where((o) => !o.horaProgramada.isAfter(hasta)).toList();
  }

  /// Id estable de una ocurrencia concreta.
  ///
  /// La clave incluye tratamiento, fecha y hora (al minuto), así que la misma
  /// ocurrencia siempre produce el mismo id y dos ocurrencias distintas no
  /// comparten id salvo colisión del hash dentro del subrango reservado.
  static int idDeOcurrencia(String tratamientoId, DateTime horaProgramada) {
    final clave =
        'alarma-puntual|$tratamientoId|${_claveMinuto(horaProgramada)}';
    return -(_baseIdAlarmaPuntual +
        (hashEstable(clave) % _tamanoIdAlarmaPuntual));
  }

  /// Ids de las ocurrencias futuras de la ventana. Atajo para cancelar.
  static List<int> idsDeOcurrencias({
    required String tratamientoId,
    required List<HorarioDia> horarios,
    required DateTime ahora,
    DateTime? fechaInicio,
    int? duracionDias,
    int dias = diasVentana,
    bool respetarVigencia = true,
  }) {
    return ocurrencias(
      tratamientoId: tratamientoId,
      horarios: horarios,
      ahora: ahora,
      fechaInicio: fechaInicio,
      duracionDias: duracionDias,
      dias: dias,
      respetarVigencia: respetarVigencia,
    ).map((o) => o.id).toList();
  }

  static String _claveMinuto(DateTime fecha) {
    final y = fecha.year.toString().padLeft(4, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final d = fecha.day.toString().padLeft(2, '0');
    final h = fecha.hour.toString().padLeft(2, '0');
    final min = fecha.minute.toString().padLeft(2, '0');
    return '$y-$m-$d-$h-$min';
  }
}
