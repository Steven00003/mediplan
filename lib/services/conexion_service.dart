import 'dart:async';

import 'package:flutter/foundation.dart';

/// Estado global del aviso discreto de "Sin conexión".
///
/// No consulta Firestore ni hace lecturas propias: las pantallas le pasan
/// `snapshot.metadata.isFromCache` de las streams que ya tienen abiertas.
///
/// El retraso existe porque al arrancar Firestore entrega primero la caché
/// local; sin él, el aviso parpadearía en cada apertura aunque hubiera red.
class ConexionService extends ChangeNotifier {
  static const Duration retrasoPorDefecto = Duration(seconds: 4);

  final Duration retraso;
  Timer? _temporizador;
  bool _sinConexion = false;

  ConexionService({this.retraso = retrasoPorDefecto});

  bool get sinConexion => _sinConexion;

  /// Informa si la última instantánea vino de caché.
  ///
  /// Varias instancias de caché seguidas no reinician el temporizador: el
  /// aviso aparece a los [retraso] segundos de la primera, no después de la
  /// última. Cualquier dato del servidor cancela la cuenta y oculta el aviso.
  void reportar(bool desdeCache) {
    if (desdeCache) {
      if (_sinConexion || _temporizador != null) return;
      _temporizador = Timer(retraso, () {
        _temporizador = null;
        if (_sinConexion) return;
        _sinConexion = true;
        notifyListeners();
      });
      return;
    }

    _temporizador?.cancel();
    _temporizador = null;
    if (!_sinConexion) return;
    _sinConexion = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _temporizador = null;
    super.dispose();
  }
}
