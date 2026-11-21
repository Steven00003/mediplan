import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado que el celular del paciente reporta al cuidador.
///
/// Lo escribe **solo** el dispositivo vinculado, en
/// `pacientes/{id}.estadoDispositivo`. El cuidador lo lee para saber si las
/// alarmas tienen condiciones para sonar (permisos, batería y última conexión).
///
/// Todos los campos son obligatorios en el mapa remoto; [fromValor] tolera
/// documentos antiguos o incompletos para que la lectura nunca rompa el detalle
/// del paciente.
class EstadoDispositivo {
  final DateTime? ultimaSincronizacion;
  final int alarmasProgramadas;
  final bool notificacionesPermitidas;
  final bool bateriaSinRestricciones;
  final int versionAndroid;
  final String fabricante;
  final String versionApp;

  const EstadoDispositivo({
    this.ultimaSincronizacion,
    required this.alarmasProgramadas,
    required this.notificacionesPermitidas,
    required this.bateriaSinRestricciones,
    required this.versionAndroid,
    required this.fabricante,
    required this.versionApp,
  });

  /// Límite del campo `fabricante` en las reglas de Firestore.
  static const int maxLargoFabricante = 40;

  /// Límite del campo `versionApp` en las reglas de Firestore.
  static const int maxLargoVersionApp = 40;

  /// Lee el mapa anidado del documento del paciente.
  ///
  /// Devuelve `null` si el campo no existe o no es un mapa: los pacientes
  /// creados antes de esta función no tienen `estadoDispositivo`.
  static EstadoDispositivo? fromValor(dynamic valor) {
    if (valor is! Map) return null;
    final map = Map<String, dynamic>.from(valor);
    return EstadoDispositivo(
      ultimaSincronizacion: _fecha(map['ultimaSincronizacion']),
      alarmasProgramadas: (map['alarmasProgramadas'] as num?)?.toInt() ?? 0,
      notificacionesPermitidas:
          map['notificacionesPermitidas'] as bool? ?? false,
      bateriaSinRestricciones: map['bateriaSinRestricciones'] as bool? ?? false,
      versionAndroid: (map['versionAndroid'] as num?)?.toInt() ?? 0,
      fabricante: _textoLimitado(map['fabricante'], maxLargoFabricante),
      versionApp: _textoLimitado(map['versionApp'], maxLargoVersionApp),
    );
  }

  /// Identidad de los valores reportados, sin la fecha del servidor.
  ///
  /// Incluye el paciente para que un cambio de paciente siempre provoque un
  /// reporte nuevo. La fecha de sincronización queda fuera: la pone Firestore
  /// con `serverTimestamp()` y no sirve para decidir si los valores cambiaron.
  String firma(String pacienteId) {
    return [
      pacienteId,
      alarmasProgramadas,
      notificacionesPermitidas ? 1 : 0,
      bateriaSinRestricciones ? 1 : 0,
      versionAndroid,
      fabricante,
      versionApp,
    ].join('|');
  }

  /// Mapa para Firestore. [ultimaSincronizacion] debe ser
  /// `FieldValue.serverTimestamp()` cuando lo escribe la app.
  Map<String, dynamic> toMap({Object? ultimaSincronizacion}) {
    return {
      'ultimaSincronizacion': ultimaSincronizacion ?? this.ultimaSincronizacion,
      'alarmasProgramadas': alarmasProgramadas,
      'notificacionesPermitidas': notificacionesPermitidas,
      'bateriaSinRestricciones': bateriaSinRestricciones,
      'versionAndroid': versionAndroid,
      'fabricante': fabricante,
      'versionApp': versionApp,
    };
  }

  static DateTime? _fecha(dynamic valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is DateTime) return valor;
    if (valor is num) {
      return DateTime.fromMillisecondsSinceEpoch(valor.toInt());
    }
    return null;
  }

  static String _textoLimitado(dynamic valor, int maximo) {
    final texto = (valor as String? ?? '').trim();
    if (texto.length <= maximo) return texto;
    return texto.substring(0, maximo);
  }
}
