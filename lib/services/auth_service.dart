import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/usuario.dart';

/// Maneja la autenticación del rol Cuidador/Doctor mediante Firebase Auth.
/// El rol Paciente NO usa login: se vincula por código (ver VinculacionService).
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get usuarioActual => _auth.currentUser;

  bool get estaLogueado => _auth.currentUser != null;

  Future<UserCredential> iniciarSesion(String correo, String contrasena) {
    return _auth.signInWithEmailAndPassword(
      email: correo.trim(),
      password: contrasena,
    );
  }

  /// Inicia sesión con Google. Devuelve true si hubo cuenta recién iniciada.
  Future<bool> iniciarSesionConGoogle() async {
    if (kIsWeb) {
      // En web google_sign_in falla con "ClientID not set"; usamos el popup de
      // Firebase Auth que toma la config de firebase_options (apiKey/domain).
      final result = await _auth.signInWithPopup(GoogleAuthProvider());
      return result.user != null;
    }
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      return false; // el usuario canceló
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
    return true;
  }

  Future<UserCredential> registrar(
    String nombre,
    String correo,
    String contrasena,
  ) {
    return _auth.createUserWithEmailAndPassword(
      email: correo.trim(),
      password: contrasena,
    );
  }

  Future<void> cerrarSesion() async {
    if (kIsWeb) {
      // En web no usamos google_sign_in (ver iniciarSesionConGoogle).
      await _auth.signOut();
      return;
    }
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión en Google: $e');
    }
    await _auth.signOut();
  }

  /// Crea/actualiza el documento del usuario en la colección [usuarios].
  Future<void> guardarPerfilUsuario({String? nombre}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .get();
    if (!doc.exists) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .set(Usuario(
            uid: user.uid,
            nombre: nombre ?? (user.displayName ?? 'Cuidador'),
            correo: user.email ?? '',
          ).toMap());
    }
  }
}
