/// Representa a un cuidador/doctor en la colección [usuarios].
class Usuario {
  final String uid;
  final String nombre;
  final String correo;

  const Usuario({
    required this.uid,
    required this.nombre,
    required this.correo,
  });

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      uid: map['uid'] as String? ?? '',
      nombre: map['nombre'] as String? ?? '',
      correo: map['correo'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nombre': nombre,
      'correo': correo,
    };
  }
}
