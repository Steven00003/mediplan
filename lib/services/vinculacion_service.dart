import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/paciente.dart';
import 'firestore_service.dart';
import 'local_store.dart';

/// Gestión del código de vinculación cuidador <-> paciente.
///
/// Formato del código: `MEDI-XXXXXX`, con X de un alfabeto sin caracteres
/// ambiguos (sin 0/O, 1/I, etc.) para que un usuario con baja alfabetización
/// lo copie sin errores.
///
/// El rol Paciente NO usa login con credenciales: se autentica de forma
/// anónima (Firebase Auth `signInAnonymously`) y el vínculo se resuelve con una
/// escritura directa a Firestore desde el cliente (sin Cloud Functions).
/// Las reglas de seguridad validan que el documento esté libre y que el UID
/// asignado (`dispositivoVinculadoId`) sea el de quien escribe.
class VinculacionService {
  final FirestoreService _fs = FirestoreService();

  static const String _alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Asegura una sesión anónima para el rol paciente (estable en el dispositivo).
  Future<void> asegurarSesionAnonima() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      // Sin conexión; se reintentará en la próxima llegada a Firestore.
    }
  }

  /// Genera un código único, p. ej. "MEDI-K4T7Q2".
  String generarCodigo() {
    final rnd = Random.secure();
    final buf = StringBuffer('MEDI-');
    for (var i = 0; i < 6; i++) {
      buf.write(_alfabeto[rnd.nextInt(_alfabeto.length)]);
    }
    return buf.toString();
  }

  /// Crea un paciente para el cuidador con su código de vinculación.
  /// Los campos de ficha (edad, condición, contacto, foto) son opcionales.
  Future<String> crearPacienteConCodigo(
    String nombre, {
    int? edad,
    String? condicion,
    String? contactoEmergencia,
    String? fotoBase64,
  }) async {
    String codigo = generarCodigo();
    // La unicidad se verifica solo entre los pacientes del propio cuidador: es
    // lo que la query necesita para ser verificable por las reglas (ver
    // `buscarPacientePorCodigo`). Sin sesión de cuidador no hay nada que
    // verificar y `crearPaciente` fallaría igual.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      try {
        while (await _fs.buscarPacientePorCodigo(codigo, uid) != null) {
          codigo = generarCodigo();
        }
      } catch (e) {
        // Si la verificación de unicidad falla (p. ej. las reglas de lectura lo
        // impiden), no bloqueamos la creación: la regla de escritura de
        // `pacientes` no exige códigos únicos.
        if (kDebugMode) {
          debugPrint('No se pudo verificar unicidad del código: $e');
        }
      }
    }
    return _fs.crearPaciente(
      nombre: nombre,
      codigoVinculacion: codigo,
      edad: edad,
      condicion: condicion,
      contactoEmergencia: contactoEmergencia,
      fotoBase64: fotoBase64,
    );
  }

  /// Valida un código y vincula este dispositivo anónimo al paciente mediante
  /// escritura directa a Firestore. Devuelve un mensaje de error legible, o
  /// null si todo salió bien.
  Future<String?> vincularPaciente(String codigo) async {
    await asegurarSesionAnonima();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return 'No se pudo iniciar sesión. Intenta de nuevo.';
    }

    final normalizado = codigo.trim().toUpperCase();
    final Paciente? paciente;
    try {
      paciente = await _fs.vincularDispositivoPorCodigo(normalizado, uid);
    } on DispositivoVinculadoAOtroException {
      return 'Este código ya está vinculado a otro dispositivo. '
          'Pide al cuidador que lo desvincule.';
    }
    if (paciente == null) {
      return 'Código inválido. Revisa el código.';
    }

    await LocalStore.guardarPacienteVinculado(paciente.id, paciente.nombre);
    await LocalStore.guardarUltimaVinculacion(
      pacienteId: paciente.id,
      codigo: paciente.codigoVinculacion.trim().isNotEmpty
          ? paciente.codigoVinculacion
          : normalizado,
      nombre: paciente.nombre,
    );
    return null;
  }

  /// El paciente ya está vinculado a este dispositivo (persiste entre reinicios).
  Future<bool> pacienteYaVinculado() async {
    final id = await LocalStore.getPacienteVinculadoId();
    return id != null && id.isNotEmpty;
  }
}
