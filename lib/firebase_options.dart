// Configuración de Firebase generada como plantilla.
//
// ⚠️ ESTE ARCHIVO ES UN PLACEHOLDER.
//
// La forma estándar de generarlo es instalar la CLI de FlutterFire y ejecutar:
//
//     dart pub global activate flutterfire_cli
//     flutterfire configure
//
// Eso lee tu proyecto de Firebase, las plataformas habilitadas (android/ios)
// y escribe este archivo con los valores correctos, además de añadir
// `google-services.json` (Android) y `GoogleService-Info.plist` (iOS).
//
// Hasta que lo corras, Firebase NO podrá conectarse. Úsalo como referencia de
// la estructura esperada.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Configuración por defecto para la plataforma actual.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Plataforma no soportada: $defaultTargetPlatform',
        );
    }
  }

  // ── REEMPLAZÁ estos valores con los de TU proyecto Firebase ──────────────
  // Podés verlos en: Consola Firebase → Ajustes del proyecto → Tus apps.

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDdDkTTLrfN7RDE3lEb0Nbbb3S3k32jskk',
    appId: '1:246766930434:android:4adc3d8aca8200d1ad351b',
    messagingSenderId: '246766930434',
    projectId: 'mediplan-35953',
    storageBucket: 'mediplan-35953.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDUdkms9hTgsWq-53ZH4VWU7Mqg0BPDTZA',
    appId: '1:246766930434:ios:bf1aa1c81e99636dad351b',
    messagingSenderId: '246766930434',
    projectId: 'mediplan-35953',
    storageBucket: 'mediplan-35953.firebasestorage.app',
    iosClientId: '246766930434-aq7e3o2r3j4it3hi4bnt06ojbrd80j8l.apps.googleusercontent.com',
    iosBundleId: 'com.mediplan.mediplan',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAt0bMsyPvPE-xNu4LpuivLH_kPyMx3FAg',
    appId: '1:246766930434:web:99553ea471a0530bad351b',
    messagingSenderId: '246766930434',
    projectId: 'mediplan-35953',
    authDomain: 'mediplan-35953.firebaseapp.com',
    storageBucket: 'mediplan-35953.firebasestorage.app',
    measurementId: 'G-YHPP533628',
  );
}
