import '../models/tratamiento.dart';
import 'vigencia_tratamiento.dart';

/// Resultado del cálculo de la siguiente toma de un tratamiento.
class ResultadoProximaToma {
  /// Fecha y hora de la siguiente toma, o `null` si no hay una siguiente.
  final DateTime? cuando;

  /// `true` cuando la toma actual es la última del tratamiento: la siguiente
  /// ocurrencia del horario caería después de la fecha de fin.
  final bool esUltima;

  const ResultadoProximaToma._({this.cuando, required this.esUltima});

  const ResultadoProximaToma.programada(DateTime fecha)
    : this._(cuando: fecha, esUltima: false);

  const ResultadoProximaToma.ultima() : this._(cuando: null, esUltima: true);
}

/// Cálculo puro de la próxima toma y de la cuenta regresiva.
class ProximaToma {
  const ProximaToma._();

  /// Calcula la siguiente toma después de [ahora], excluyendo la toma actual.
  ///
  /// [tomaActual] es la fecha/hora de la ranura que tiene abierta la pantalla de
  /// alarma. Se excluye por clave de minuto: si la app abrió la alarma unos
  /// minutos antes (ventana de -5 min), esa misma toma no debe aparecer como
  /// "próxima".
  ///
  /// Se recorren los `HorarioDia` por día de calendario, así que los cruces de
  /// medianoche y de semana salen solos. Si la siguiente ocurrencia cae después
  /// de la fecha de fin del tratamiento, devuelve [ResultadoProximaToma.ultima].
  static ResultadoProximaToma calcular({
    required Tratamiento tratamiento,
    required DateTime ahora,
    required DateTime tomaActual,
  }) {
    final claveActual = _claveMinuto(tomaActual);
    final fin = VigenciaTratamiento.fechaFin(tratamiento);
    final candidatos = <DateTime>[];
    final vistas = <String>{};

    // 15 días cubren cualquier horario semanal, incluso si solo aplica un día.
    for (var offset = 0; offset <= 15; offset++) {
      final dia = DateTime(ahora.year, ahora.month, ahora.day + offset);
      for (final horario in tratamiento.horarios) {
        if (!horario.dias.contains(dia.weekday)) continue;
        final partes = horario.hora.split(':');
        if (partes.length != 2) continue;
        final hora = int.tryParse(partes[0]);
        final minuto = int.tryParse(partes[1]);
        if (hora == null || minuto == null) continue;
        if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) continue;

        final candidato = DateTime(dia.year, dia.month, dia.day, hora, minuto);
        if (!candidato.isAfter(ahora)) continue;
        if (_claveMinuto(candidato) == claveActual) continue;
        if (fin != null && _soloFecha(candidato).isAfter(_soloFecha(fin))) {
          continue;
        }
        if (!VigenciaTratamiento.estaVigente(tratamiento, candidato)) {
          continue;
        }
        if (vistas.add(_claveMinuto(candidato))) candidatos.add(candidato);
      }
    }

    if (candidatos.isEmpty) return const ResultadoProximaToma.ultima();
    candidatos.sort();
    return ResultadoProximaToma.programada(candidatos.first);
  }

  /// Formato de la cuenta regresiva:
  ///
  /// - menos de 1 minuto: `Faltan 42 s`;
  /// - menos de 1 hora: `Faltan 59 min 05 s`;
  /// - menos de 1 día: `Faltan 3 h 25 min`;
  /// - un día o más: `Faltan 1 d 3 h 25 min`.
  static String formatearCuentaRegresiva(Duration restante) {
    var total = restante.inSeconds;
    if (total < 0) total = 0;

    if (total < 60) return 'Faltan $total s';

    final dias = total ~/ Duration.secondsPerDay;
    final horas = (total % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
    final minutos =
        (total % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final segundos = total % Duration.secondsPerMinute;

    if (total < Duration.secondsPerHour) {
      return 'Faltan $minutos min ${segundos.toString().padLeft(2, '0')} s';
    }
    if (total < Duration.secondsPerDay) {
      return 'Faltan $horas h $minutos min';
    }
    return 'Faltan $dias d $horas h $minutos min';
  }

  static String _claveMinuto(DateTime fecha) {
    final y = fecha.year.toString().padLeft(4, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final d = fecha.day.toString().padLeft(2, '0');
    final h = fecha.hour.toString().padLeft(2, '0');
    final min = fecha.minute.toString().padLeft(2, '0');
    return '$y-$m-$d-$h-$min';
  }

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);
}
