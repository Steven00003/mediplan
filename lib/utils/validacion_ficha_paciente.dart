/// Reglas de validación de la ficha editable del paciente.
///
/// Es lógica pura para poder probarla sin Flutter ni Firestore. La usan tanto
/// la pantalla de alta (`NuevoPacienteScreen`) como la de edición
/// (`EditarPacienteScreen`) para que no haya dos criterios distintos.
class FichaPacienteValidada {
  final String nombre;
  final int? edad;
  final String? condicion;
  final String? contactoEmergencia;

  const FichaPacienteValidada({
    required this.nombre,
    required this.edad,
    required this.condicion,
    required this.contactoEmergencia,
  });
}

class ResultadoValidacionFicha {
  final FichaPacienteValidada? datos;
  final String? error;

  const ResultadoValidacionFicha._({this.datos, this.error});

  bool get esValida => datos != null;

  factory ResultadoValidacionFicha.ok(FichaPacienteValidada datos) =>
      ResultadoValidacionFicha._(datos: datos);

  factory ResultadoValidacionFicha.error(String mensaje) =>
      ResultadoValidacionFicha._(error: mensaje);
}

const int edadMinimaPaciente = 0;
const int edadMaximaPaciente = 120;
const int telefonoMinDigitos = 7;
const int telefonoMaxDigitos = 15;
const int condicionMaxCaracteres = 80;

/// Quita espacios al inicio/fin y colapsa los espacios internos.
String normalizarNombrePaciente(String texto) {
  return texto.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Normaliza un texto opcional: vacío se convierte en `null`.
String? normalizarTextoOpcional(String texto) {
  final normalizado = texto.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalizado.isEmpty ? null : normalizado;
}

/// Valida y normaliza los campos editables de la ficha.
///
/// El teléfono acepta un `+` inicial y espacios mientras se escribe, pero se
/// guarda sin espacios (por ejemplo `+34 600 000 000` → `+34600000000`).
ResultadoValidacionFicha validarFichaPaciente({
  required String nombre,
  required String edad,
  required String condicion,
  required String contactoEmergencia,
}) {
  final nombreNormalizado = normalizarNombrePaciente(nombre);
  if (nombreNormalizado.isEmpty) {
    return ResultadoValidacionFicha.error('Ingresa el nombre del paciente.');
  }

  int? edadNormalizada;
  final edadTexto = edad.trim();
  if (edadTexto.isNotEmpty) {
    final edadParseada = int.tryParse(edadTexto);
    if (edadParseada == null ||
        edadParseada < edadMinimaPaciente ||
        edadParseada > edadMaximaPaciente) {
      return ResultadoValidacionFicha.error(
        'La edad debe estar entre $edadMinimaPaciente y '
        '$edadMaximaPaciente años.',
      );
    }
    edadNormalizada = edadParseada;
  }

  final condicionNormalizada = normalizarTextoOpcional(condicion);
  if (condicionNormalizada != null &&
      condicionNormalizada.length > condicionMaxCaracteres) {
    return ResultadoValidacionFicha.error(
      'La condición no puede superar los $condicionMaxCaracteres caracteres.',
    );
  }

  String? contactoNormalizado;
  final contactoTexto = contactoEmergencia.trim();
  if (contactoTexto.isNotEmpty) {
    final compacto = contactoTexto.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\+?\d+$').hasMatch(compacto)) {
      return ResultadoValidacionFicha.error(
        'El teléfono debe tener entre $telefonoMinDigitos y '
        '$telefonoMaxDigitos dígitos.',
      );
    }
    final digitos = compacto.replaceAll('+', '').length;
    if (digitos < telefonoMinDigitos || digitos > telefonoMaxDigitos) {
      return ResultadoValidacionFicha.error(
        'El teléfono debe tener entre $telefonoMinDigitos y '
        '$telefonoMaxDigitos dígitos.',
      );
    }
    contactoNormalizado = compacto;
  }

  return ResultadoValidacionFicha.ok(
    FichaPacienteValidada(
      nombre: nombreNormalizado,
      edad: edadNormalizada,
      condicion: condicionNormalizada,
      contactoEmergencia: contactoNormalizado,
    ),
  );
}
