import 'package:cloud_firestore/cloud_firestore.dart';

/// Estados posibles de una toma programada.
enum EstadoToma {
  pendiente, // programada, aún sin respuesta del paciente
  tomada, // paciente confirmó con "YA"
  tardia, // confirmada, pero después de un tiempo razonable
  olvidada, // pasó el plazo sin confirmación
  pospuesta, // paciente eligió "Recordar" (se reagendó)
}

extension EstadoTomaExt on EstadoToma {
  String get nombre {
    switch (this) {
      case EstadoToma.pendiente:
        return 'pendiente';
      case EstadoToma.tomada:
        return 'tomó';
      case EstadoToma.tardia:
        return 'tardó';
      case EstadoToma.olvidada:
        return 'olvidó';
      case EstadoToma.pospuesta:
        return 'pospuesta';
    }
  }

  static EstadoToma fromNombre(String? nombre) {
    switch (nombre) {
      case 'tomó':
        return EstadoToma.tomada;
      case 'tardó':
        return EstadoToma.tardia;
      case 'olvidó':
        return EstadoToma.olvidada;
      case 'pospuesta':
        return EstadoToma.pospuesta;
      default:
        return EstadoToma.pendiente;
    }
  }

  /// El estado cierra la cuenta de la toma: ya no se espera nada más de ella.
  ///
  /// "pendiente" y "pospuesta" NO son terminales a propósito. Posponer
  /// reagenda el aviso, así que una toma pospuesta sigue sin resolverse y puede
  /// acabar en "olvidada" si el paciente nunca la confirma. Es el mismo criterio
  /// que usa el chequeo de alarma de `medicamentos_proximos_screen.dart`.
  bool get esTerminal =>
      this == EstadoToma.tomada ||
      this == EstadoToma.tardia ||
      this == EstadoToma.olvidada;

  /// Si este estado implica una hora de confirmación real.
  ///
  /// "pendiente" no llegó a confirmarse y "olvidada" es justamente una toma que
  /// NUNCA se confirmó: sellarle una hora de confirmación mentiría sobre lo que
  /// pasó. Para el resto, el momento en que se escribió el registro es la
  /// confirmación.
  bool get registraConfirmacion =>
      this != EstadoToma.pendiente && this != EstadoToma.olvidada;
}

/// Registro de una toma: la dosis programada y su confirmación.
class RegistroToma {
  final String id;
  final String tratamientoId;
  final String pacienteId;
  final DateTime horaProgramada;
  final DateTime? horaConfirmacion;
  final EstadoToma estado;

  const RegistroToma({
    required this.id,
    required this.tratamientoId,
    required this.pacienteId,
    required this.horaProgramada,
    this.horaConfirmacion,
    required this.estado,
  });

  RegistroToma copyWith({
    DateTime? horaConfirmacion,
    EstadoToma? estado,
  }) {
    return RegistroToma(
      id: id,
      tratamientoId: tratamientoId,
      pacienteId: pacienteId,
      horaProgramada: horaProgramada,
      horaConfirmacion: horaConfirmacion ?? this.horaConfirmacion,
      estado: estado ?? this.estado,
    );
  }

  factory RegistroToma.fromMap(String id, Map<String, dynamic> map) {
    return RegistroToma(
      id: id,
      tratamientoId: map['tratamientoId'] as String? ?? '',
      pacienteId: map['pacienteId'] as String? ?? '',
      horaProgramada:
          (map['horaProgramada'] as Timestamp?)?.toDate() ?? DateTime.now(),
      horaConfirmacion: (map['horaConfirmacion'] as Timestamp?)?.toDate(),
      estado: EstadoTomaExt.fromNombre(map['estado'] as String?),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tratamientoId': tratamientoId,
      'pacienteId': pacienteId,
      'horaProgramada': horaProgramada,
      'horaConfirmacion': horaConfirmacion,
      'estado': estado.nombre,
    };
  }
}
