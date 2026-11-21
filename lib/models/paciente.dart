import 'estado_dispositivo.dart';

/// Representa a un paciente en la colección [pacientes].
///
/// El vínculo entre el dispositivo del paciente y su perfil se resuelve
/// mediante `codigoVinculacion` (generado por el cuidador) y
/// `dispositivoVinculadoId` (identificador local persistido en el teléfono).
///
/// Los campos de ficha [edad], [condicion], [contactoEmergencia] y [fotoBase64]
/// son OPCIONALES: los documentos creados antes de que existieran los tienen en
/// null (o con el campo ausente), y eso debe seguir leyéndose sin error.
///
/// [cuidadorFcmToken] es el token de push del cuidador, espejado aquí (y no solo
/// en `usuarios/{uid}`) porque el dispositivo del paciente —sesión anónima— es
/// quien envía la notificación y las reglas no le dejan leer el documento del
/// cuidador. También es OPCIONAL: puede faltar mientras el cuidador no haya
/// abierto su app con permiso de notificaciones.
class Paciente {
  final String id;
  final String nombre;
  final String cuidadorId;
  final String codigoVinculacion;
  final String? dispositivoVinculadoId;
  final int? edad;
  final String? condicion;
  final String? contactoEmergencia;
  final String? fotoBase64;
  final String? cuidadorFcmToken;

  /// Reporte del celular del paciente. Es `null` en documentos antiguos o
  /// mientras el paciente no haya abierto esta versión de la app.
  final EstadoDispositivo? estadoDispositivo;

  const Paciente({
    required this.id,
    required this.nombre,
    required this.cuidadorId,
    required this.codigoVinculacion,
    this.dispositivoVinculadoId,
    this.edad,
    this.condicion,
    this.contactoEmergencia,
    this.fotoBase64,
    this.cuidadorFcmToken,
    this.estadoDispositivo,
  });

  Paciente copyWith({
    String? dispositivoVinculadoId,
    int? edad,
    String? condicion,
    String? contactoEmergencia,
    String? fotoBase64,
    String? cuidadorFcmToken,
    EstadoDispositivo? estadoDispositivo,
  }) {
    return Paciente(
      id: id,
      nombre: nombre,
      cuidadorId: cuidadorId,
      codigoVinculacion: codigoVinculacion,
      dispositivoVinculadoId:
          dispositivoVinculadoId ?? this.dispositivoVinculadoId,
      edad: edad ?? this.edad,
      condicion: condicion ?? this.condicion,
      contactoEmergencia: contactoEmergencia ?? this.contactoEmergencia,
      fotoBase64: fotoBase64 ?? this.fotoBase64,
      cuidadorFcmToken: cuidadorFcmToken ?? this.cuidadorFcmToken,
      estadoDispositivo: estadoDispositivo ?? this.estadoDispositivo,
    );
  }

  factory Paciente.fromMap(String id, Map<String, dynamic> map) {
    return Paciente(
      id: id,
      nombre: map['nombre'] as String? ?? '',
      cuidadorId: map['cuidadorId'] as String? ?? '',
      codigoVinculacion: map['codigoVinculacion'] as String? ?? '',
      dispositivoVinculadoId: map['dispositivoVinculadoId'] as String?,
      // `num` y no `int`: los documentos de la consola a veces guardan el valor
      // como double, y un cast directo a int rompería la lectura.
      edad: (map['edad'] as num?)?.toInt(),
      condicion: map['condicion'] as String?,
      contactoEmergencia: map['contactoEmergencia'] as String?,
      fotoBase64: map['fotoBase64'] as String?,
      cuidadorFcmToken: map['cuidadorFcmToken'] as String?,
      estadoDispositivo: EstadoDispositivo.fromValor(map['estadoDispositivo']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'cuidadorId': cuidadorId,
      'codigoVinculacion': codigoVinculacion,
      'dispositivoVinculadoId': dispositivoVinculadoId,
      // Opcionales: se escriben siempre, valiendo null cuando no se rellenaron.
      'edad': edad,
      'condicion': condicion,
      'contactoEmergencia': contactoEmergencia,
      'fotoBase64': fotoBase64,
      'cuidadorFcmToken': cuidadorFcmToken,
      // `estadoDispositivo` NO se incluye a propósito: lo escribe únicamente el
      // dispositivo del paciente con `actualizarEstadoDispositivo`. Así una
      // edición del cuidador no lo borra ni lo pisa.
    };
  }
}
