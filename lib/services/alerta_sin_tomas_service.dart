import '../models/registro_toma.dart';
import '../models/tratamiento.dart';
import '../utils/vigencia_tratamiento.dart';

/// Cálculo puro de la alerta de "5 días sin tomas" de un tratamiento.
///
/// La alerta es **por tratamiento** y solo mira días de calendario completos:
/// hoy nunca cuenta, porque todavía puede confirmarse una toma. Se saltan los
/// días en los que el tratamiento no tiene ninguna dosis programada; no son
/// días "sin toma".
class AlertaSinTomasService {
  const AlertaSinTomasService._();

  /// Días programados consecutivos (no necesariamente seguidos en el
  /// calendario) que deben estar sin ninguna confirmación.
  static const int diasRequeridos = 5;

  /// Si [tratamiento] está en alerta para [ahora].
  ///
  /// Requiere inicio conocido y tratamiento vigente. Si el tratamiento empezó
  /// hace menos de [diasRequeridos] días programados, no dispara.
  static bool hayAlerta({
    required Tratamiento tratamiento,
    required List<RegistroToma> registros,
    required DateTime ahora,
  }) {
    final dias = _ultimosDiasProgramados(tratamiento, ahora);
    if (dias == null) return false;

    for (final dia in dias) {
      final hayConfirmacion = registros.any(
        (r) =>
            r.tratamientoId == tratamiento.id &&
            _mismoDia(r.horaProgramada, dia) &&
            _esConfirmacion(r),
      );
      if (hayConfirmacion) return false;
    }
    return true;
  }

  /// Primer día de la ventana que hay que leer para evaluar la alerta.
  ///
  /// Es el más antiguo de los últimos [diasRequeridos] días programados. Sirve
  /// para que la reconciliación pida los registros necesarios incluso con un
  /// horario semanal (5 semanas atrás), sin leer desde el inicio del
  /// tratamiento.
  static DateTime? inicioVentanaAlerta(
    Tratamiento tratamiento,
    DateTime ahora,
  ) {
    final dias = _ultimosDiasProgramados(tratamiento, ahora);
    return dias?.first;
  }

  /// Los últimos [diasRequeridos] días programados anteriores a hoy, del más
  /// antiguo al más reciente. `null` si no hay suficientes o no aplica.
  static List<DateTime>? _ultimosDiasProgramados(
    Tratamiento tratamiento,
    DateTime ahora,
  ) {
    final inicio = tratamiento.fechaInicio;
    if (inicio == null) return null;
    if (!VigenciaTratamiento.estaVigente(tratamiento, ahora)) return null;
    if (!_tieneAlgunHorarioValido(tratamiento)) return null;

    final desde = _soloFecha(inicio);
    final hoy = _soloFecha(ahora);
    var dia = DateTime(hoy.year, hoy.month, hoy.day - 1);
    final encontrados = <DateTime>[];

    while (!dia.isBefore(desde)) {
      if (_tieneTomaProgramada(tratamiento, dia)) {
        encontrados.add(dia);
        if (encontrados.length == diasRequeridos) {
          return encontrados.reversed.toList();
        }
      }
      // Resta un día de calendario, no 24 h absolutas: así el cambio de hora
      // de verano no desplaza la ventana.
      dia = DateTime(dia.year, dia.month, dia.day - 1);
    }
    return null;
  }

  static bool _tieneTomaProgramada(Tratamiento tratamiento, DateTime dia) {
    for (final horario in tratamiento.horarios) {
      if (!_esHorarioValido(horario)) continue;
      if (horario.dias.contains(dia.weekday)) return true;
    }
    return false;
  }

  static bool _tieneAlgunHorarioValido(Tratamiento tratamiento) =>
      tratamiento.horarios.any(_esHorarioValido);

  static bool _esHorarioValido(HorarioDia horario) {
    if (!horario.dias.any((d) => d >= 1 && d <= 7)) return false;
    final partes = horario.hora.split(':');
    if (partes.length != 2) return false;
    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);
    return hora != null &&
        minuto != null &&
        hora >= 0 &&
        hora <= 23 &&
        minuto >= 0 &&
        minuto <= 59;
  }

  /// Solo una toma realmente tomada cuenta como confirmación.
  ///
  /// `pospuesta` tiene hora de confirmación (marca el momento de posponer),
  /// pero no es una toma; `olvidada` tampoco y además suele tenerla null.
  static bool _esConfirmacion(RegistroToma registro) {
    final tomadaOTardia =
        registro.estado == EstadoToma.tomada ||
        registro.estado == EstadoToma.tardia;
    return tomadaOTardia && registro.horaConfirmacion != null;
  }

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
