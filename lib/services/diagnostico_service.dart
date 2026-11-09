import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Metadatos de una notificación programada.
///
/// El plugin solo expone id, título, cuerpo y payload en
/// `pendingNotificationRequests()`, así que guardamos aquí lo que hace falta
/// para el diagnóstico: tipo, hora/día y modo de programación. La pantalla de
/// diagnóstico cruza esta lista con las solicitudes que Android aún tiene
/// pendientes, de modo que una alarma ya disparada no aparece.
class ProgramacionAlarma {
  final int id;
  final String tipo;
  final String? tratamientoId;
  final String? hora;
  final int? dia;
  final String modo;
  final DateTime? proxima;
  final bool semanal;

  const ProgramacionAlarma({
    required this.id,
    required this.tipo,
    required this.modo,
    this.tratamientoId,
    this.hora,
    this.dia,
    this.proxima,
    this.semanal = false,
  });

  /// Próxima hora local. Para las programaciones semanales se recalcula desde
  /// [hora] y [dia], porque la fecha guardada al programar queda en el pasado
  /// después de que la alarma se dispara y el plugin reprograma la siguiente.
  DateTime? proximaLocal(DateTime ahora) {
    if (semanal && hora != null && dia != null) {
      final partes = hora!.split(':');
      if (partes.length != 2) return proxima;
      final h = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      if (h == null || m == null) return proxima;
      var cuando = DateTime(ahora.year, ahora.month, ahora.day, h, m);
      while (cuando.weekday != dia || !cuando.isAfter(ahora)) {
        cuando = cuando.add(const Duration(days: 1));
      }
      return cuando;
    }
    return proxima;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tipo': tipo,
    'tratamientoId': tratamientoId,
    'hora': hora,
    'dia': dia,
    'modo': modo,
    'proxima': proxima?.millisecondsSinceEpoch,
    'semanal': semanal,
  };

  factory ProgramacionAlarma.fromJson(Map<String, dynamic> json) {
    final ms = json['proxima'];
    return ProgramacionAlarma(
      id: (json['id'] as num).toInt(),
      tipo: json['tipo'] as String? ?? 'desconocida',
      tratamientoId: json['tratamientoId'] as String?,
      hora: json['hora'] as String?,
      dia: (json['dia'] as num?)?.toInt(),
      modo: json['modo'] as String? ?? 'desconocido',
      proxima: ms is num
          ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
          : null,
      semanal: json['semanal'] as bool? ?? false,
    );
  }
}

/// Un intento de abrir la app desde una notificación de alarma.
class IntentoAperturaAlarma {
  final DateTime fecha;
  final String payload;
  final String resultado;
  final String motivo;

  const IntentoAperturaAlarma({
    required this.fecha,
    required this.payload,
    required this.resultado,
    required this.motivo,
  });

  Map<String, dynamic> toJson() => {
    'fecha': fecha.millisecondsSinceEpoch,
    'payload': payload,
    'resultado': resultado,
    'motivo': motivo,
  };

  factory IntentoAperturaAlarma.fromJson(Map<String, dynamic> json) {
    return IntentoAperturaAlarma(
      fecha: DateTime.fromMillisecondsSinceEpoch(
        (json['fecha'] as num?)?.toInt() ?? 0,
      ),
      payload: json['payload'] as String? ?? '',
      resultado: json['resultado'] as String? ?? '',
      motivo: json['motivo'] as String? ?? '',
    );
  }
}

/// Persistencia local del diagnóstico de alarmas.
///
/// No toca Firestore ni la lógica de confirmación/posposición. Todos los
/// métodos son best-effort: un fallo de almacenamiento no puede romper una
/// alarma.
class DiagnosticoService {
  static const _kIntentos = 'diagnostico_intentos_alarma_v1';
  static const _kProgramaciones = 'diagnostico_programaciones_alarma_v1';
  static const int maxIntentos = 20;

  Future<void> registrarIntento({
    required String payload,
    required String resultado,
    required String motivo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = prefs.getStringList(_kIntentos) ?? <String>[];
      final nuevo = IntentoAperturaAlarma(
        fecha: DateTime.now(),
        payload: payload,
        resultado: resultado,
        motivo: motivo,
      );
      lista.insert(0, jsonEncode(nuevo.toJson()));
      if (lista.length > maxIntentos) {
        lista.removeRange(maxIntentos, lista.length);
      }
      await prefs.setStringList(_kIntentos, lista);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo guardar el intento de alarma: $e');
      }
    }
  }

  Future<List<IntentoAperturaAlarma>> obtenerIntentos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = prefs.getStringList(_kIntentos) ?? <String>[];
      return lista
          .map((s) {
            try {
              return IntentoAperturaAlarma.fromJson(
                jsonDecode(s) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<IntentoAperturaAlarma>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> limpiarIntentos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kIntentos);
    } catch (_) {}
  }

  Future<void> guardarProgramacion(ProgramacionAlarma programacion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = prefs.getStringList(_kProgramaciones) ?? <String>[];
      final sinDuplicados = <String>[];
      for (final s in lista) {
        try {
          final p = ProgramacionAlarma.fromJson(
            jsonDecode(s) as Map<String, dynamic>,
          );
          if (p.id != programacion.id) sinDuplicados.add(s);
        } catch (_) {
          // Una entrada corrupta se descarta al reescribir.
        }
      }
      sinDuplicados.insert(0, jsonEncode(programacion.toJson()));
      if (sinDuplicados.length > 200) {
        sinDuplicados.removeRange(200, sinDuplicados.length);
      }
      await prefs.setStringList(_kProgramaciones, sinDuplicados);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo guardar la programación de alarma: $e');
      }
    }
  }

  Future<void> eliminarProgramacion(int id) async {
    await eliminarProgramaciones([id]);
  }

  Future<void> eliminarProgramaciones(Iterable<int> ids) async {
    final aBorrar = ids.toSet();
    if (aBorrar.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = prefs.getStringList(_kProgramaciones) ?? <String>[];
      final conservadas = <String>[];
      for (final s in lista) {
        try {
          final p = ProgramacionAlarma.fromJson(
            jsonDecode(s) as Map<String, dynamic>,
          );
          if (!aBorrar.contains(p.id)) conservadas.add(s);
        } catch (_) {
          // Se descarta la entrada corrupta.
        }
      }
      await prefs.setStringList(_kProgramaciones, conservadas);
    } catch (_) {}
  }

  Future<void> limpiarProgramaciones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kProgramaciones);
    } catch (_) {}
  }

  Future<List<ProgramacionAlarma>> obtenerProgramaciones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = prefs.getStringList(_kProgramaciones) ?? <String>[];
      return lista
          .map((s) {
            try {
              return ProgramacionAlarma.fromJson(
                jsonDecode(s) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<ProgramacionAlarma>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
