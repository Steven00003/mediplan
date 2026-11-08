import '../models/registro_toma.dart';
import '../models/tratamiento.dart';
import '../services/omitidas_service.dart';
import 'registros_toma.dart';

/// Cómo resume un día entero de tomas la tira de los últimos 7 días.
///
/// El orden de la enumeración ES el orden de gravedad: [diaConFaltas] es el
/// peor caso y [diaPerfecto] el mejor. La tira de la UI usa el color del primer
/// valor que aplique, así que agregar uno obliga a revisarla.
enum EstadoDia {
  /// El horario no genera ninguna dosis ese día (por ejemplo, tratamientos de
  /// lunes a viernes: el fin de semana no aparece). No es un fallo ni un logro:
  /// no cuenta ni para bien ni para mal.
  sinDosis,

  /// Hubo al menos una dosis y ninguna quedó a medias.
  diaPerfecto,

  /// Hubo tardías pero ninguna falta: se tomó todo, pero con retraso.
  conTardias,

  /// Alguna dosis sin confirmar: olvidada, o directamente sin registro.
  diaConFaltas,
}

/// Cómo se agruparon las dosis **esperadas** de un día en lo que realmente pasó.
class ResumenDia {
  /// El día a las 00:00, para comparar por día de calendario y no por instante.
  final DateTime dia;

  /// Dosis que el horario del paciente pedía ese día, ya con el filtro por día de
  /// la semana aplicado.
  final int esperadas;

  /// Confirmadas dentro del plazo de 15 minutos.
  final int aTiempo;

  /// Confirmadas, pero pasado ese plazo.
  final int tardias;

  /// Con marca explícita de `olvidada`, escrita por la reconciliación.
  final int olvidadas;

  /// Sin ningún registro terminal: ni confirmadas ni marcadas. Es el hueco que
  /// deja el modelo sin backend cuando la app estuvo cerrada.
  final int sinRegistro;

  const ResumenDia({
    required this.dia,
    this.esperadas = 0,
    this.aTiempo = 0,
    this.tardias = 0,
    this.olvidadas = 0,
    this.sinRegistro = 0,
  });

  /// Lo que no llegó a cerrarse: lo perdido y lo que ni siquiera quedó anotado.
  int get sinConfirmar => olvidadas + sinRegistro;

  /// Todo lo que tiene estado terminal, sea cual sea.
  int get resueltas => aTiempo + tardias + olvidadas;

  EstadoDia get estado {
    if (esperadas == 0) return EstadoDia.sinDosis;
    if (sinConfirmar > 0) return EstadoDia.diaConFaltas;
    if (tardias > 0) return EstadoDia.conTardias;
    return EstadoDia.diaPerfecto;
  }
}

/// Cumplimiento de un paciente en una ventana de días.
class ResumenCumplimiento {
  /// Los días de la ventana en **orden cronológico** (del más antiguo al más
  /// reciente; el último es hoy).
  final List<ResumenDia> dias;

  ResumenCumplimiento(this.dias);

  /// Conteo total de la ventana. Se suman los días y no se cuentan
  /// `RegistroToma` sueltos porque a una misma dosis le pueden quedar dos
  /// documentos: el paciente pospone y luego confirma, o la reconciliación se
  /// cruza con una confirmación.
  int get esperadas => dias.fold(0, (a, d) => a + d.esperadas);
  int get aTiempo => dias.fold(0, (a, d) => a + d.aTiempo);
  int get tardias => dias.fold(0, (a, d) => a + d.tardias);
  int get olvidadas => dias.fold(0, (a, d) => a + d.olvidadas);
  int get sinRegistro => dias.fold(0, (a, d) => a + d.sinRegistro);

  /// Lo perdido más lo no anotado: la cifra que de verdad mide el descuido.
  int get sinConfirmar => olvidadas + sinRegistro;

  /// Sin datos suficientes para decir un porcentaje. No se muestra `0%` porque
  /// "el paciente no tiene horarios" y "el paciente falló todo" no son lo mismo.
  bool get hayDatos => esperadas > 0;

  /// Porcentaje de dosis a tiempo, o `null` si la ventana no espera ninguna.
  double? get porcentajeATiempo {
    if (!hayDatos) return null;
    return aTiempo / esperadas * 100;
  }

  /// Días consecutivos y completos terminados hasta ayer.
  ///
  /// Reglas, todas deliberadas:
  ///  - **hoy queda fuera**: el día en curso está incompleto por definición y
  ///    rompería la racha siempre;
  ///  - **un día sin dosis esperadas ni suma ni rompe** (el fin de semana de un
  ///    paciente de lunes a viernes no es un logro ni un fallo);
  ///  - **una tardía sí rompe**: la racha es de días sin fallos, y se define como
  ///    "todo a tiempo" para que la métrica no premie el llegar tarde;
  ///  - se mira **como máximo [rachaConfianza] días hacia atrás**, porque más
  ///    allá la reconciliación puede no haber corrido y un día vacío no
  ///    significaría nada (ver `OmitidasService.ventanaDias`).
  int get racha {
    // Los días van del más antiguo al más reciente, así que el límite de
    // confianza es el FINAL de la lista, no el principio.
    final desde = dias.length - rachaConfianza;
    var cuenta = 0;
    var lastIndex = dias.length - 2; // ayer
    for (var i = dias.length - 2; i >= desde; i--) {
      final d = dias[i];
      if (d.esperadas == 0) continue; // ni cuenta ni rompe
      // Debe ser consecutivo al último día contado (calendar consecutivo)
      if (cuenta > 0 && (lastIndex - i) > 1) break;
      if (d.estado != EstadoDia.diaPerfecto) break;
      cuenta++;
      lastIndex = i;
    }
    return cuenta;
  }

  /// Días que la racha puede mirar hacia atrás.
  ///
  /// Mismo tope que la reconciliación y por el mismo motivo: más allá de una
  /// semana sin abrir la app no hay registros que prueben nada.
  static const int rachaConfianza = 7;
}

/// Resume [dias] días de cumplimiento terminando en [ahora].
///
/// [tratamientos] decide qué dosis **debían** darse: sin ellos no hay
/// denominador, porque `registrosToma` no guarda nada para una dosis que nadie
/// tocó (`pendiente` no tiene ningún camino que lo produzca). [registros] son los
/// documentos reales de la ventana.
///
/// Es pura y por eso va aquí, en vez de dentro de la pantalla: se puede probar
/// con listas escritas a mano, sin Firebase ni widgets, igual que
/// `resumen_horario.dart` y `etiqueta_toma.dart`.
ResumenCumplimiento resumenCumplimiento({
  required List<Tratamiento> tratamientos,
  required List<RegistroToma> registros,
  required DateTime ahora,
  required int dias,
}) {
  if (dias < 1) return ResumenCumplimiento(const []);

  // Los registros del móvil llegan como `DateTime` de zona local, pero las
  // pruebas los escriben con `DateTime(2026, ...)`, que es UTC. Comparar el año
  // sin normalizar rompe el filtro por día de la semana, así que se normaliza
  // una sola vez acá.
  final ref = ahora.isUtc ? ahora.toLocal() : ahora;

  // Índice por clave de ranura. Se conserva un solo registro por dosis: el
  // terminal con la primera confirmación. Así los duplicados viejos (varios
  // "YA" sobre la misma ranura) no cuentan dos veces y una confirmación gana
  // sobre una marca de olvidada.
  final porClave = <String, RegistroToma>{
    for (final r in RegistrosToma.deduplicarPorRanura(registros))
      RegistrosToma.clave(r): r,
  };

  final inicioHoy = DateTime(ref.year, ref.month, ref.day);
  final resumenes = <ResumenDia>[];

  for (var offset = dias - 1; offset >= 0; offset--) {
    final dia = inicioHoy.subtract(Duration(days: offset));
    final slots = OmitidasService.ranurasDelDia(tratamientos, dia);

    var aTiempo = 0, tardias = 0, olvidadas = 0, sinRegistro = 0;
    for (final slot in slots) {
      final r = porClave[slot.clave];
      if (r == null) {
        sinRegistro++;
      } else if (r.estado == EstadoToma.tomada) {
        aTiempo++;
      } else if (r.estado == EstadoToma.tardia) {
        tardias++;
      } else if (r.estado == EstadoToma.olvidada) {
        olvidadas++;
      } else {
        // Solo `pospuesta` (o un estado no terminal): el paciente pidió que le
        // recordaran más tarde y la ranura sigue sin resolverse.
        sinRegistro++;
      }
    }

    resumenes.add(ResumenDia(
      dia: dia,
      esperadas: slots.length,
      aTiempo: aTiempo,
      tardias: tardias,
      olvidadas: olvidadas,
      sinRegistro: sinRegistro,
    ));
  }

  return ResumenCumplimiento(resumenes);
}


