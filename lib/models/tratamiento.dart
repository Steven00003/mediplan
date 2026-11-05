import 'package:cloud_firestore/cloud_firestore.dart';

/// Un horario de toma: una hora concreta y los días de la semana en que aplica.
///
/// [hora] usa el formato "HH:mm" (24h), ej. "08:00".
/// [dias] usa la numeración ISO 8601: 1 = lunes … 7 = domingo.
///
/// Antes de este modelo, `Tratamiento.horarios` era una lista de horas sueltas
/// (sin días). Esos documentos se siguen leyendo: al no traer días se asume que
/// aplican todos los días (ver [Tratamiento.fromMap]).
class HorarioDia {
  final String hora;
  final List<int> dias;

  const HorarioDia({required this.hora, required this.dias});

  /// Un horario que aplica de lunes a domingo.
  static const List<int> todosLosDias = [1, 2, 3, 4, 5, 6, 7];

  factory HorarioDia.fromMap(Map<String, dynamic> map) {
    final diasRaw = map['dias'];
    return HorarioDia(
      hora: map['hora'] as String? ?? '',
      // Si el campo `dias` falta por completo se asume diario; una lista
      // explícita (aunque venga vacía) se respeta tal cual.
      dias: diasRaw is List
          ? diasRaw.map((e) => (e as num).toInt()).toList()
          : todosLosDias,
    );
  }

  Map<String, dynamic> toMap() => {'hora': hora, 'dias': dias};

  @override
  String toString() => '$hora ${dias.join('-')}';
}

/// Representa un tratamiento (medicamento) de un paciente.
///
/// [horarios] es una lista de [HorarioDia] (hora + días de la semana en que
/// aplica), ej. [HorarioDia(hora: "08:00", dias: [1, 2, 3, 4, 5])].
/// [frecuencia] describe cada cuántas horas o veces al día, ej. "2 veces al día".
/// [duracion] es texto libre opcional sobre cuánto dura el tratamiento, ej.
/// "7 días" o "Continuo". Se conserva para mostrarlo; la finalización real usa
/// [duracionDias] y [fechaInicio], no este texto.
/// [duracionDias] es la duración numérica en días. `null` significa continuo o
/// desconocido (documentos antiguos): en ambos casos no se calcula finalización.
/// [fechaInicio] es la fecha local (sin hora) desde la que cuenta el tratamiento.
/// `null` en documentos antiguos significa "inicio desconocido"; no se calcula
/// tiempo restante ni finalización hasta que el cuidador los edite y guarde.
/// [ultimoAvisoSinTomas] es la fecha local del último push de "5 días sin tomas"
/// enviado al cuidador. Se usa para no repetir el aviso el mismo día.
/// [fotoBase64] es la foto real del medicamento codificada en base64 (con data
/// URI) y guardada dentro del propio documento de Firestore, mostrada en la
/// pantalla de alarma.
class Tratamiento {
  final String id;
  final String pacienteId;
  final String nombreMedicamento;
  final String? fotoBase64;
  final String dosis;
  final List<HorarioDia> horarios;
  final String frecuencia;
  final String? duracion;
  final DateTime? fechaInicio;
  final int? duracionDias;
  final DateTime? ultimoAvisoSinTomas;

  const Tratamiento({
    required this.id,
    required this.pacienteId,
    required this.nombreMedicamento,
    this.fotoBase64,
    required this.dosis,
    required this.horarios,
    required this.frecuencia,
    this.duracion,
    this.fechaInicio,
    this.duracionDias,
    this.ultimoAvisoSinTomas,
  });

  factory Tratamiento.fromMap(String id, Map<String, dynamic> map) {
    return Tratamiento(
      id: id,
      pacienteId: map['pacienteId'] as String? ?? '',
      nombreMedicamento: map['nombreMedicamento'] as String? ?? '',
      fotoBase64: map['fotoBase64'] as String?,
      dosis: map['dosis'] as String? ?? '1',
      horarios: _parseHorarios(map['horarios']),
      frecuencia: map['frecuencia'] as String? ?? '',
      // Opcional: los documentos anteriores a este campo lo traen ausente.
      duracion: map['duracion'] as String?,
      fechaInicio: _parseFecha(map['fechaInicio']),
      duracionDias: _parseEnteroPositivo(map['duracionDias']),
      ultimoAvisoSinTomas: _parseFecha(map['ultimoAvisoSinTomas']),
    );
  }

  /// Normaliza una fecha de Firestore a fecha local sin hora.
  ///
  /// Se aceptan `Timestamp` (lo que escribe `toMap` al pasar por Firestore) y
  /// `DateTime` (tests y documentos ya normalizados en memoria). Cualquier otro
  /// valor se trata como inicio desconocido.
  static DateTime? _parseFecha(Object? raw) {
    if (raw is Timestamp) {
      final d = raw.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    return null;
  }

  static int? _parseEnteroPositivo(Object? raw) {
    final n = raw is num ? raw.toInt() : int.tryParse('$raw');
    return n != null && n > 0 ? n : null;
  }

  /// Normaliza el campo `horarios` de un documento de Firestore.
  ///
  /// Formatos aceptados:
  ///  - Nuevo: `[{'hora': '08:00', 'dias': [1, 2, 3]}, ...]`.
  ///  - Antiguo (compatibilidad): `['08:00', '20:00']`; cada hora pasa a
  ///    aplicar todos los días, de modo que el comportamiento no cambia.
  static List<HorarioDia> _parseHorarios(Object? raw) {
    if (raw is! List) return const [];
    final resultado = <HorarioDia>[];
    for (final e in raw) {
      if (e is HorarioDia) {
        resultado.add(e);
      } else if (e is String) {
        resultado.add(HorarioDia(hora: e, dias: HorarioDia.todosLosDias));
      } else if (e is Map) {
        resultado.add(HorarioDia.fromMap(Map<String, dynamic>.from(e)));
      }
    }
    return resultado;
  }

  Map<String, dynamic> toMap() {
    return {
      'pacienteId': pacienteId,
      'nombreMedicamento': nombreMedicamento,
      'fotoBase64': fotoBase64,
      'dosis': dosis,
      // Siempre el formato nuevo: lista de {hora, dias}.
      'horarios': horarios.map((h) => h.toMap()).toList(),
      'frecuencia': frecuencia,
      'duracion': duracion,
      'fechaInicio': fechaInicio,
      'duracionDias': duracionDias,
      'ultimoAvisoSinTomas': ultimoAvisoSinTomas,
    };
  }
}
