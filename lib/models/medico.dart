import 'package:cloud_firestore/cloud_firestore.dart';

/// Perfil público del cuidador/doctor, visible para sus pacientes vinculados.
///
/// Vive en `medicos/{uid}` y solo contiene datos pensados para mostrarse al
/// paciente: nombre, título/estudios, especialidad y una miniatura de la foto.
class Medico {
  final String uid;
  final String nombre;
  final String titulo;
  final String especialidad;
  final String? fotoBase64;
  final DateTime? actualizadoEn;

  const Medico({
    required this.uid,
    required this.nombre,
    required this.titulo,
    required this.especialidad,
    this.fotoBase64,
    this.actualizadoEn,
  });

  factory Medico.fromMap(String uid, Map<String, dynamic> map) {
    final raw = map['actualizadoEn'];
    return Medico(
      uid: uid,
      nombre: map['nombre'] as String? ?? '',
      titulo: map['titulo'] as String? ?? '',
      especialidad: map['especialidad'] as String? ?? '',
      fotoBase64: map['fotoBase64'] as String?,
      actualizadoEn: raw is Timestamp
          ? raw.toDate()
          : raw is DateTime
          ? raw
          : null,
    );
  }

  Map<String, dynamic> toMap({Object? actualizadoEn}) {
    return {
      'nombre': nombre.trim(),
      'titulo': titulo.trim(),
      'especialidad': especialidad.trim(),
      'fotoBase64': fotoBase64,
      'actualizadoEn': actualizadoEn ?? FieldValue.serverTimestamp(),
    };
  }
}
