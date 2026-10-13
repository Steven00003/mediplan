import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/paciente.dart';
import '../models/registro_toma.dart';
import '../models/tratamiento.dart';

/// Capa de acceso a Firestore.
///
/// Toda operación depende de las reglas de seguridad (ver `firestore.rules` en la raíz):
/// un cuidador solo toca sus pacientes; un paciente vinculado solo sus datos.
class FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ---------------------------------------------------------------------
  // Pacientes (lado cuidador)
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _pacientesCollection() =>
      _db.collection('pacientes');

  CollectionReference<Map<String, dynamic>> _vinculosCollection() =>
      _db.collection('vinculos');

  String get _cuidadorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Stream en tiempo real de los pacientes del cuidador logueado.
  Stream<List<Paciente>> streamPacientesDelCuidador() {
    return _pacientesCollection()
        .where('cuidadorId', isEqualTo: _cuidadorId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Paciente.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<Paciente>> streamPacientePorDispositivo(String dispositivoId) {
    return _pacientesCollection()
        .where('dispositivoVinculadoId', isEqualTo: dispositivoId)
        .limit(1)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Paciente.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Stream del documento del paciente (usado por el modo paciente para
  /// detectar desvinculación o borrado del perfil).
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamPacienteDoc(
    String pacienteId,
  ) {
    return _pacientesCollection().doc(pacienteId).snapshots();
  }

  Future<Paciente?> getPaciente(
    String pacienteId, {
    GetOptions? options,
  }) async {
    final doc = await _pacientesCollection().doc(pacienteId).get(options);
    if (!doc.exists) return null;
    return Paciente.fromMap(doc.id, doc.data()!);
  }

  /// Crea un paciente y devuelve el id del documento generado.
  Future<String> crearPaciente({
    required String nombre,
    required String codigoVinculacion,
    int? edad,
    String? condicion,
    String? contactoEmergencia,
    String? fotoBase64,
  }) async {
    final cuidadorId = _cuidadorId;
    if (cuidadorId.isEmpty) {
      throw StateError(
        'No hay una sesión de cuidador activa; no se puede crear el paciente.',
      );
    }
    final doc = await _pacientesCollection().add(
      Paciente(
        id: '',
        nombre: nombre,
        cuidadorId: cuidadorId,
        codigoVinculacion: codigoVinculacion,
        // SIEMPRE '' en un paciente nuevo, nunca null ni omitido: la búsqueda
        // de vinculación filtra por `dispositivoVinculadoId == ''` y un filtro
        // `== ''` NO coincide con un campo null (que es lo que emite `toMap()`
        // cuando el campo viene sin asignar).
        dispositivoVinculadoId: '',
        edad: edad,
        condicion: condicion,
        contactoEmergencia: contactoEmergencia,
        fotoBase64: fotoBase64,
      ).toMap(),
    );
    try {
      await _vinculosCollection().doc(codigoVinculacion).set({
        'pacienteId': doc.id,
      });
    } catch (e) {
      // Intento de limpiar el paciente creado si falla el registro de vínculo.
      try {
        await doc.delete();
      } catch (_) {}
      rethrow;
    }
    return doc.id;
  }

  /// Vincula permanentemente el dispositivo del paciente a su perfil.
  /// [dispositivoId] debe ser el token local persistido (ver LocalStore).
  Future<void> vincularDispositivoAPaciente(
    String pacienteId,
    String dispositivoId,
  ) async {
    await _pacientesCollection().doc(pacienteId).update({
      'dispositivoVinculadoId': dispositivoId,
    });
  }

  /// Guarda el token FCM del cuidador en todos SUS pacientes.
  ///
  /// Va en `pacientes/{id}.cuidadorFcmToken` y no en `usuarios/{uid}` porque el
  /// que envía el push es el dispositivo del paciente (sesión anónima) y las
  /// reglas no le dejan leer el documento del cuidador; sí puede leer el suyo.
  /// Solo el cuidador escribe este campo (la regla de `update` ya lo permite).
  ///
  /// Es idempotente: solo escribe los documentos cuyo token difiere, para que
  /// el listener de pacientes del dashboard no entre en bucle.
  Future<void> guardarTokenCuidador(String token) async {
    final uid = _cuidadorId;
    if (uid.isEmpty || token.isEmpty) return;
    final snap = await _pacientesCollection()
        .where('cuidadorId', isEqualTo: uid)
        .get();
    for (final doc in snap.docs) {
      if (doc.data()['cuidadorFcmToken'] == token) continue;
      await doc.reference.update({'cuidadorFcmToken': token});
    }
  }

  /// Borra el token del cuidador de sus pacientes, para que este dispositivo
  /// deje de recibir avisos de la cuenta que cierra sesión.
  Future<void> limpiarTokenCuidador() async {
    final uid = _cuidadorId;
    if (uid.isEmpty) return;
    final snap = await _pacientesCollection()
        .where('cuidadorId', isEqualTo: uid)
        .get();
    for (final doc in snap.docs) {
      if (doc.data()['cuidadorFcmToken'] == null) continue;
      await doc.reference.update({
        'cuidadorFcmToken': FieldValue.delete(),
      });
    }
  }

  // ---------------------------------------------------------------------
  // Tratamientos
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _tratamientosCollection() =>
      _db.collection('tratamientos');

  /// Stream de tratamientos de un paciente (usado por el paciente).
  Stream<List<Tratamiento>> streamTratamientosDePaciente(String pacienteId) {
    return _tratamientosCollection()
        .where('pacienteId', isEqualTo: pacienteId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Tratamiento.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<String> crearTratamiento(Tratamiento tratamiento) async {
    final doc = await _tratamientosCollection().add(tratamiento.toMap());
    return doc.id;
  }

  Future<Tratamiento?> getTratamiento(String id) async {
    final doc = await _tratamientosCollection().doc(id).get();
    if (!doc.exists) return null;
    return Tratamiento.fromMap(doc.id, doc.data()!);
  }

  Future<void> actualizarTratamiento(Tratamiento tratamiento) async {
    await _tratamientosCollection()
        .doc(tratamiento.id)
        .update(tratamiento.toMap());
  }

  Future<void> eliminarTratamiento(String id) async {
    await _tratamientosCollection().doc(id).delete();
  }

  // ---------------------------------------------------------------------
  // Registros de toma
  // ---------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _registrosCollection() =>
      _db.collection('registrosToma');

  /// Crea el registro de una toma. Por defecto queda "pendiente"; si se pasa
  /// [estado] distinto, se fija la hora de confirmación al momento actual.
  ///
  /// [idDoc] fuerza el id del documento en lugar de dejar que lo genere
  /// Firestore. Las tomas olvidadas lo usan para que dos reconciliaciones
  /// solapadas escriban el mismo documento en vez de crear dos.
  ///
  /// `horaConfirmacion` queda en null salvo que el estado realmente implique una
  /// confirmación (ver `EstadoToma.registraConfirmacion`): una toma olvidada
  /// no se confirmó nunca y no debe llevar hora de confirmación.
  Future<void> crearRegistroToma({
    required String tratamientoId,
    required String pacienteId,
    required DateTime horaProgramada,
    EstadoToma estado = EstadoToma.pendiente,
    String? idDoc,
  }) async {
    final col = _registrosCollection();
    final ahora = DateTime.now();
    final registro = RegistroToma(
      id: idDoc ?? '',
      tratamientoId: tratamientoId,
      pacienteId: pacienteId,
      horaProgramada: horaProgramada,
      horaConfirmacion: estado.registraConfirmacion ? ahora : null,
      estado: estado,
    );
    if (idDoc != null) {
      await col.doc(idDoc).set(registro.toMap());
    } else {
      await col.add(registro.toMap());
    }
  }

  /// Confirma la toma con estado [estado]. Devuelve el registro actualizado.
  Future<void> confirmarToma({
    required String registroId,
    required EstadoToma estado,
  }) async {
    await _registrosCollection().doc(registroId).update({
      'horaConfirmacion': DateTime.now(),
      'estado': estado.nombre,
    });
  }

  /// Registros de un paciente con `horaProgramada` dentro de `[desde, hasta)`.
  ///
  /// Es el rango que necesita la reconciliación de tomas olvidadas, que a
  /// diferencia de [streamTomasPendientesHoy] no mira solo hoy: si el paciente
  /// estuvo días sin abrir la app, hay que poder recuperar esas tomas para
  /// marcar las perdidas.
  ///
  /// resuelven el acceso con un `get()` al documento del paciente, así que la
  /// query solo está autorizada si sus propios filtros lo demuestran. Sin él
  /// la consulta se deniega (403), aunque los datos sean del propio paciente.
  ///
  /// OJO: esta combinación de igualdad + rango sobre `horaProgramada` necesita
  /// un índice compuesto que solo existe en la consola de Firebase. Si aparece
  /// `FAILED_PRECONDITION` ("requires an index") hay que crearlo ahí; desplegar
  /// `firestore.indexes.json` no sirve porque está vacío.
  Future<List<RegistroToma>> getRegistrosEnRango(
    String pacienteId,
    DateTime desde,
    DateTime hasta,
  ) async {
    final snap = await _registrosCollection()
        .where('pacienteId', isEqualTo: pacienteId)
        .where('horaProgramada', isGreaterThanOrEqualTo: desde)
        .where('horaProgramada', isLessThan: hasta)
        .get();
    return snap.docs.map((d) => RegistroToma.fromMap(d.id, d.data())).toList();
  }

  /// Registros de toma recientes de un paciente (para el dashboard del cuidador).
  Stream<List<RegistroToma>> streamRegistrosDePaciente(
    String pacienteId, {
    int limite = 20,
  }) {
    return _registrosCollection()
        .where('pacienteId', isEqualTo: pacienteId)
        .orderBy('horaProgramada', descending: true)
        .limit(limite)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => RegistroToma.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  /// Registros de toma más recientes de un paciente, en una sola lectura.
  ///
  /// Es [streamRegistrosDePaciente] pero con `.get()` en vez de `.snapshots()`:
  /// lo usan las pantallas que calculan estadísticas, que deben leer una vez y
  /// pintar el resultado, no resuscribirse en cada confirmación.
  ///
  /// La forma de la query es **deliberadamente idéntica** a la de
  /// `streamRegistrosDePaciente` —y no la de [getRegistrosEnRango], que además
  /// lleva dos límites de rango sobre `horaProgramada`— para no depender de si el
  /// índice compuesto que ya sirve a esta alcanza también a una consulta con
  /// rango. Los índices compuestos solo existen en la consola de Firebase y no
  /// se pueden desplegar desde el repo, así que no hay forma de comprobar desde
  /// el código que dos formas distintas de query compartan índice: se reutiliza
  /// la que la app ya usa en producción.
  ///
  /// [limite] es un tope duro: la ventana de 30 días de las estadísticas puede
  /// superarlo en pacientes con muchos medicamentos, y el recorte se avisa en
  /// pantalla en vez de mostrar cifras silenciosamente incompletas.
  Future<List<RegistroToma>> getRegistrosRecientes(
    String pacienteId, {
    int limite = 500,
  }) async {
    final snap = await _registrosCollection()
        .where('pacienteId', isEqualTo: pacienteId)
        .orderBy('horaProgramada', descending: true)
        .limit(limite)
        .get();
    return snap.docs.map((d) => RegistroToma.fromMap(d.id, d.data())).toList();
  }

  /// Stream en tiempo real de los registros de toma de varios pacientes
  /// (usado por el dashboard del cuidador para reflejar confirmaciones al vivo).
  ///
  /// [pacienteIds] se traduce a `where in` (máx. 10 por consulta). Con más de 10
  /// pacientes se agrupa en varias consultas y se combinan sus resultados.
  /// Devuelve los registros más recientes primero.
  Stream<List<RegistroToma>> streamRegistrosDePacientes(
    List<String> pacienteIds, {
    int limite = 50,
  }) {
    final ids = pacienteIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return Stream.value(const []);
    }

    Stream<List<RegistroToma>> subconsulta(List<String> grupo) {
      return _registrosCollection()
          .where('pacienteId', whereIn: grupo)
          .orderBy('horaProgramada', descending: true)
          .limit(limite)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => RegistroToma.fromMap(d.id, d.data()))
                .toList(),
          );
    }

    final grupos = <List<String>>[];
    for (var i = 0; i < ids.length; i += 10) {
      grupos.add(ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10));
    }

    return _fusionarStreams(grupos.map(subconsulta).toList(), limite);
  }

  /// Combina varios streams de listas en uno solo, emitiendo la lista fusionada
  /// y ordenada (más recientes primero) en cada cambio de cualquiera de ellos.
  Stream<List<RegistroToma>> _fusionarStreams(
    List<Stream<List<RegistroToma>>> streams,
    int limite,
  ) {
    final subs = <StreamSubscription>[];
    final ultimos = List<List<RegistroToma>?>.filled(streams.length, null);

    late final StreamController<List<RegistroToma>> controller;

    void emitir() {
      final todos = <RegistroToma>[];
      for (final u in ultimos) {
        if (u != null) todos.addAll(u);
      }
      todos.sort((a, b) => b.horaProgramada.compareTo(a.horaProgramada));
      controller.add(todos.take(limite).toList());
    }

    controller = StreamController<List<RegistroToma>>(
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );

    for (var i = 0; i < streams.length; i++) {
      subs.add(
        streams[i].listen((lista) {
          ultimos[i] = lista;
          emitir();
        }, onError: controller.addError),
      );
    }
    return controller.stream;
  }

  /// Stream de tomas "pendientes" de hoy para un tratamiento, usadas por la
  /// pantalla de alarma del paciente.
  Stream<List<RegistroToma>> streamTomasPendientesHoy(
    String pacienteId,
    String tratamientoId,
  ) {
    final inicio = DateTime.now();
    final inicioDia = DateTime(inicio.year, inicio.month, inicio.day);
    final finDia = inicioDia.add(const Duration(days: 1));
    return _registrosCollection()
        .where('pacienteId', isEqualTo: pacienteId)
        .where('tratamientoId', isEqualTo: tratamientoId)
        .where('horaProgramada', isGreaterThanOrEqualTo: inicioDia)
        .where('horaProgramada', isLessThan: finDia)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => RegistroToma.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  // ---------------------------------------------------------------------
  // Código de vinculación
  // ---------------------------------------------------------------------

  /// Busca, entre los pacientes del cuidador [uid], el que tiene este código de
  /// vinculación. Devuelve null si no existe.
  ///
  /// `pacientes` es una disyunción (`uid == cuidadorId` OR
  /// `uid == dispositivoVinculadoId` OR doc libre) y Firestore solo autoriza
  /// una *query* si puede probar, usando los filtros de la propia query, que
  /// todos los documentos devueltos cumplen la regla. Filtrar solo por
  /// `codigoVinculacion` no prueba nada sobre esa disyunción → 403 "Missing or
  /// insufficient permissions", aunque el documento sea del propio cuidador.
  /// Replicar la condición de la regla dentro de la query es lo que la hace
  /// verificable.
  Future<Paciente?> buscarPacientePorCodigo(String codigo, String uid) async {
    final snap = await _pacientesCollection()
        .where('codigoVinculacion', isEqualTo: codigo.trim().toUpperCase())
        .where('cuidadorId', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Paciente.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  /// Vincula este dispositivo anónimo al paciente cuyo código coincide, usando
  /// escritura directa a Firestore (sin Cloud Functions).
  ///
  /// Resuelve el código en `/vinculos` y va **directo** al `update` de
  /// `pacientes/{id}`, sin leer el documento antes: la rama de `update` de las
  /// reglas valida por sí sola que el documento esté libre (`estaLibre`), que el
  /// UID asignado sea el del escritor y que `codigoVinculacion`/`cuidadorId` no
  /// cambien. Una lectura previa daría `permission-denied`: el dispositivo
  /// anónimo todavía no es el dueño del documento.
  ///
  /// Devuelve el paciente leído **después** del update exitoso — en ese punto
  /// el dispositivo ya es `esDispositivoVinculado` y sí puede leer la ficha —
  /// o null si el código no existe o el update es rechazado (el documento ya
  /// estaba vinculado a otro dispositivo).
  Future<Paciente?> vincularDispositivoPorCodigo(
    String codigo,
    String uid,
  ) async {
    final normalizado = codigo.trim().toUpperCase();
    final vinculo = await _vinculosCollection().doc(normalizado).get();
    if (!vinculo.exists) return null;
    final pacienteId = vinculo.data()?['pacienteId'] as String?;
    if (pacienteId == null || pacienteId.isEmpty) return null;

    try {
      await _pacientesCollection().doc(pacienteId).update({
        'dispositivoVinculadoId': uid,
      });
    } catch (_) {
      return null;
    }

    Paciente? leido;
    try {
      final doc = await _pacientesCollection().doc(pacienteId).get();
      if (doc.exists) leido = Paciente.fromMap(doc.id, doc.data()!);
    } catch (_) {
      leido = null;
    }
    if (leido != null) return leido;
    // Esta lectura no debiera fallar (el dispositivo ya es el dueño); si lo
    // hiciera, devolvemos al menos el id para no mostrar "código inválido"
    // con un vínculo que sí se creó.
    return Paciente(
      id: pacienteId,
      nombre: '',
      cuidadorId: '',
      codigoVinculacion: normalizado,
      dispositivoVinculadoId: uid,
    );
  }

  /// Desvincula el dispositivo del paciente dejando `dispositivoVinculadoId`
  /// vacío (que las reglas de `firestore.rules` tratan como "libre").
  /// Solo el cuidador dueño puede: las reglas exigen que quien escribe sea el
  /// `cuidadorId` del documento.
  Future<void> desvincularDispositivo(String pacienteId) async {
    await _pacientesCollection().doc(pacienteId).update({
      'dispositivoVinculadoId': '',
    });

    final paciente = await getPaciente(pacienteId);
    // Misma normalización que el resto del flujo (`buscarPacientePorCodigo`,
    // `vincularDispositivoPorCodigo`, la migración): con espacios o
    // minúsculas, el índice se escribiría bajo una clave que el lookup
    // normalizado nunca encuentra, dejando un `/vinculos` duplicado.
    final codigo = paciente?.codigoVinculacion.trim().toUpperCase() ?? '';
    if (codigo.isNotEmpty) {
      await _vinculosCollection().doc(codigo).set({
        'pacienteId': pacienteId,
      });
    }
  }
}
