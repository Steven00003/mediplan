import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/tratamiento.dart';
import '../utils/hash_estable.dart';
import '../utils/ventana_alarmas.dart';
import '../utils/vigencia_tratamiento.dart';
import 'diagnostico_service.dart';

/// Datos que acompañan al toque de una alarma.
///
/// [idNotificacion] es el id que Android le asignó a la notificación mostrada;
/// se usa para quitarla de la barra al confirmar o posponer sin cancelar las
/// demás ocurrencias de la ventana de alarmas.
class PayloadAlarma {
  final String payload;
  final int? idNotificacion;

  const PayloadAlarma(this.payload, {this.idNotificacion});
}

/// Notificaciones locales programadas para la alarma de cada medicamento.
///
/// Funcionan **sin conexión**: se programan en el dispositivo para la hora
/// exacta de cada toma. La confirmación se sincroniza con Firestore cuando
/// vuelva a haber conexión.
class NotificacionesService {
  static final NotificacionesService _instancia =
      NotificacionesService._interno();
  factory NotificacionesService() => _instancia;
  NotificacionesService._interno();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Payload de la última alarma tocada, pendiente de que la app termine de
  /// arrancar y `AppState` sepa qué paciente está vinculado.
  ///
  /// Se usa un `ValueNotifier` porque el callback del plugin puede llegar antes
  /// de que `BootstrapScreen` esté montado; el valor queda guardado y el
  /// listener lo procesa cuando la app está lista.
  final ValueNotifier<PayloadAlarma?> _payloadPendiente =
      ValueNotifier<PayloadAlarma?>(null);
  ValueListenable<PayloadAlarma?> get payloadPendiente => _payloadPendiente;

  /// Ids de los canales. Se exponen porque el AndroidManifest los referencia:
  /// las notificaciones que muestra FCM con la app en segundo plano/cerrada
  /// necesitan que el canal ya exista (Android 8+ descarta las notificaciones
  /// cuyo canal no esté creado).
  static const String canalAlarmasId = 'alarmas_medicamentos';
  static const String canalCuidadorId = 'alertas_cuidador';
  static const String canalAvisoPrevioId = 'avisos_previos';
  static const String canalFelicitacionesId = 'felicitaciones';
  static const String canalRecordatoriosTardiosId = 'recordatorios_tardios';

  /// Payload de las notificaciones de recordatorio tardío. No es un payload de
  /// alarma: al tocarlo solo se abre la app, no la pantalla de alarma. Se usa
  /// además para cancelar los recordatorios puntuales de un tratamiento.
  static const String _prefijoPayloadRecordatorio = 'recordatorio|';

  /// Payload de la alarma de prueba del diagnóstico. No escribe en Firestore:
  /// solo abre una pantalla mínima con la hora programada y la hora real.
  static const String prefijoPayloadPrueba = 'prueba|';

  /// Id fijo de la alarma de prueba. Se cancela antes de programar otra para
  /// que no queden pruebas acumuladas.
  static const int idAlarmaPrueba = 0x7FFFFFF0;

  /// Canal nativo para datos del sistema que Dart no expone: la zona IANA real,
  /// el nivel de API y el permiso de pantalla completa. `inicializar()` lo usa
  /// para que `timezone` no se quede en UTC por defecto.
  static const MethodChannel _canalSistema = MethodChannel(
    'com.mediplan.mediplan/diagnostico',
  );

  static const _channel = AndroidNotificationDetails(
    canalAlarmasId,
    'Alarmas de medicamentos',
    channelDescription: 'Recordatorios de toma de medicamentos de MediPlan',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    ongoing: true,
  );

  static const _canalCuidador = AndroidNotificationDetails(
    canalCuidadorId,
    'Alertas de tus pacientes',
    channelDescription:
        'Avisos en tiempo real de confirmaciones de tomas de tus pacientes',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Aviso suave 5 minutos antes de la toma. Sin fullScreenIntent ni tono de
  /// alarma: es un recordatorio amable, no la alarma principal.
  static const _canalAvisoPrevio = AndroidNotificationDetails(
    canalAvisoPrevioId,
    'Avisos previos',
    channelDescription: 'Aviso cinco minutos antes de cada toma',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    enableVibration: false,
    audioAttributesUsage: AudioAttributesUsage.notification,
    category: AndroidNotificationCategory.reminder,
  );

  /// Felicitación inmediata al confirmar. Sin sonido: el paciente acaba de
  /// interactuar con la alarma y no queremos sumar otro tono.
  static const _canalFelicitaciones = AndroidNotificationDetails(
    canalFelicitacionesId,
    'Felicitaciones',
    channelDescription: 'Mensajes positivos al confirmar una toma',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: false,
    enableVibration: false,
    category: AndroidNotificationCategory.status,
  );

  /// Recordatorio tardío: más insistente que el aviso previo, pero sin
  /// fullScreenIntent y con audio de notificación (no de alarma).
  static const _canalRecordatorioTardio = AndroidNotificationDetails(
    canalRecordatoriosTardiosId,
    'Recordatorios tardíos',
    channelDescription: 'Recordatorios amables si una toma sigue pendiente',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
    category: AndroidNotificationCategory.reminder,
  );

  /// Inicializa el plugin, fija la zona local y crea los canales.
  /// Se llama una vez desde `BootstrapScreen`.
  Future<void> inicializar() async {
    tz.initializeTimeZones();
    await _configurarZonaHorariaLocal();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _alRecibirRespuesta,
    );

    // Si la app estaba cerrada y se abrió tocando la alarma (o por su
    // fullScreenIntent), el payload llega por aquí, no por el callback.
    try {
      final lanzamiento = await _plugin.getNotificationAppLaunchDetails();
      if (lanzamiento?.didNotificationLaunchApp ?? false) {
        final respuesta = lanzamiento?.notificationResponse;
        _registrarPayload(respuesta?.payload, idNotificacion: respuesta?.id);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo leer el lanzamiento por notificación: $e');
      }
    }

    await _crearCanales();
  }

  /// Recibe el toque de una notificación con la app ya en marcha.
  void _alRecibirRespuesta(NotificationResponse respuesta) {
    _registrarPayload(respuesta.payload, idNotificacion: respuesta.id);
  }

  void _registrarPayload(String? payload, {int? idNotificacion}) {
    final limpio = payload?.trim();
    if (limpio == null || limpio.isEmpty) return;
    // Los recordatorios tardíos no abren la pantalla de alarma.
    if (limpio.startsWith(_prefijoPayloadRecordatorio)) return;
    _payloadPendiente.value = PayloadAlarma(
      limpio,
      idNotificacion: idNotificacion,
    );
  }

  /// Devuelve el payload pendiente y lo borra para no abrirlo dos veces.
  PayloadAlarma? tomarPayloadPendiente() {
    final payload = _payloadPendiente.value;
    _payloadPendiente.value = null;
    return payload;
  }

  /// Fija `tz.local` en la zona IANA real del dispositivo.
  ///
  /// `tz.initializeTimeZones()` deja `tz.local` en UTC. Si no se corrige, un
  /// horario de las 08:00 se interpreta como 08:00 UTC y la alarma suena a la
  /// hora equivocada (o se reprograma para otro día).
  Future<void> _configurarZonaHorariaLocal() async {
    try {
      final id = await _canalSistema.invokeMethod<String>('timeZoneId');
      if (id == null || id.isEmpty) return;
      tz.setLocalLocation(tz.getLocation(id));
    } catch (e) {
      // En tests o fuera de Android el canal no existe. Se mantiene el
      // comportamiento anterior (UTC) en vez de romper el arranque.
      if (kDebugMode) {
        debugPrint('No se pudo configurar la zona horaria local: $e');
      }
    }
  }

  /// Crea los canales explícitamente.
  ///
  /// Android 8+ descarta una notificación cuyo canal no exista. Las alarmas
  /// locales lo crean al vuelo, pero las que muestra FCM con la app cerrada no:
  /// necesitan que [canalCuidadorId] exista de antemano (su id va en el
  /// AndroidManifest como `default_notification_channel_id`).
  Future<void> _crearCanales() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalAlarmasId,
        'Alarmas de medicamentos',
        description: 'Recordatorios de toma de medicamentos de MediPlan',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalCuidadorId,
        'Alertas de tus pacientes',
        description:
            'Avisos en tiempo real de confirmaciones de tomas de tus pacientes',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalAvisoPrevioId,
        'Avisos previos',
        description: 'Aviso cinco minutos antes de cada toma',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalFelicitacionesId,
        'Felicitaciones',
        description: 'Mensajes positivos al confirmar una toma',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalRecordatoriosTardiosId,
        'Recordatorios tardíos',
        description: 'Recordatorios amables si una toma sigue pendiente',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
  }

  /// Pide permiso para mostrar notificaciones (Android 13+ / iOS).
  Future<void> pedirPermiso() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Nivel de API de Android, o `null` si el canal nativo no está disponible.
  Future<int?> androidSdkInt() async {
    try {
      return await _canalSistema.invokeMethod<int>('androidSdkInt');
    } catch (_) {
      return null;
    }
  }

  /// Indica si Android permite abrir la alarma a pantalla completa.
  ///
  /// En Android < 14 el permiso no existe y el canal devuelve `true`.
  Future<bool?> puedeUsarPantallaCompleta() async {
    try {
      return await _canalSistema.invokeMethod<bool>('canUseFullScreenIntent');
    } catch (_) {
      return null;
    }
  }

  /// Abre la pantalla de Ajustes donde se concede el permiso de pantalla
  /// completa (Android 14+). Devuelve si quedó concedido al volver.
  Future<bool?> solicitarPermisoPantallaCompleta() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return android?.requestFullScreenIntentPermission();
  }

  /// Indica si la app puede mostrar notificaciones.
  Future<bool?> notificacionesHabilitadas() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      return await android?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// Canal real de alarmas tal como está registrado en el dispositivo.
  ///
  /// Es la fuente para diagnosticar si el usuario bajó la importancia del canal
  /// después de instalarlo (Android no permite que la app la vuelva a subir).
  Future<AndroidNotificationChannel?> canalDeAlarmas() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      final canales = await android?.getNotificationChannels();
      for (final canal in canales ?? const <AndroidNotificationChannel>[]) {
        if (canal.id == canalAlarmasId) return canal;
      }
    } catch (_) {}
    return null;
  }

  /// Notificaciones que Android todavía tiene pendientes de disparar.
  Future<List<PendingNotificationRequest>> solicitudesPendientes() async {
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (_) {
      return const [];
    }
  }

  /// Indica si Android permite programar alarmas exactas (API 31+).
  Future<bool?> puedeProgramarAlarmasExactas() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      return await android?.canScheduleExactNotifications();
    } catch (_) {
      return null;
    }
  }

  /// Abre los Ajustes para permitir alarmas exactas. Devuelve si quedó
  /// concedido al volver.
  Future<bool?> solicitarPermisoAlarmasExactas() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      return await android?.requestExactAlarmsPermission();
    } catch (_) {
      return null;
    }
  }

  /// Estado de energía/Doze/No molestar que Dart no expone.
  Future<Map<String, dynamic>?> estadoEnergia() async {
    try {
      return await _canalSistema.invokeMapMethod<String, dynamic>(
        'estadoEnergia',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> abrirAjustesNotificaciones() async {
    try {
      await _canalSistema.invokeMethod<void>('abrirAjustesNotificaciones');
    } catch (_) {}
  }

  Future<void> abrirAjustesBateria() async {
    try {
      await _canalSistema.invokeMethod<void>('abrirAjustesBateria');
    } catch (_) {}
  }

  Future<void> abrirAjustesAlarmasExactas() async {
    try {
      await _canalSistema.invokeMethod<void>('abrirAjustesAlarmasExactas');
    } catch (_) {}
  }

  /// Programa una alarma **puntual** (una sola ejecución) para un horario
  /// HH:mm.
  ///
  /// Despite the name, this does NOT repeat: it is only used by "Recordar"
  /// (posponer) in `alarma_screen.dart`, which wants exactly one alarm a few
  /// minutes later. The repeating alarms for a treatment use
  /// [programarAlarmasDeHorario].
  ///
  /// [payload] lleva el id del registro de toma para que la pantalla de
  /// alarma pueda identificarlo al abrirse.
  Future<void> programarAlarmaDiaria({
    required int id,
    required String hora,
    required String nombreMedicamento,
    required String payload,
  }) async {
    final partes = hora.split(':');
    final horaLocal = tz.TZDateTime(
      tz.local,
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      int.parse(partes[0]),
      int.parse(partes[1]),
    );
    final horaSiguiente = horaLocal.isBefore(tz.TZDateTime.now(tz.local))
        ? horaLocal.add(const Duration(days: 1))
        : horaLocal;

    await _plugin.zonedSchedule(
      id,
      'Hora de tu medicina',
      '$nombreMedicamento - Hora de tomarla',
      horaSiguiente,
      const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: payload,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    await _guardarProgramacion(
      id: id,
      tipo: 'posponer',
      tratamientoId: payload.split('|').first,
      hora: hora,
      dia: horaSiguiente.weekday,
      modo: AndroidScheduleMode.alarmClock,
      proxima: horaSiguiente,
      semanal: false,
    );
  }

  /// Programa la alarma de prueba del diagnóstico: una sola ejecución en
  /// [en] (60 s por defecto) con el mismo canal, `alarmClock` y
  /// `fullScreenIntent` que la alarma real. No escribe en Firestore.
  Future<void> programarAlarmaDePrueba({
    Duration en = const Duration(seconds: 60),
  }) async {
    final cuando = tz.TZDateTime.now(tz.local).add(en);
    final payload = '$prefijoPayloadPrueba${cuando.millisecondsSinceEpoch}';

    await cancelarAlarmaDePrueba();
    await _plugin.zonedSchedule(
      idAlarmaPrueba,
      'Prueba de alarma',
      'Alarma de prueba de MediPlan. Debe abrir la pantalla de prueba.',
      cuando,
      const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: payload,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    await _guardarProgramacion(
      id: idAlarmaPrueba,
      tipo: 'prueba',
      modo: AndroidScheduleMode.alarmClock,
      proxima: cuando,
      semanal: false,
    );
  }

  /// Cancela la alarma de prueba y quita sus metadatos del diagnóstico.
  Future<void> cancelarAlarmaDePrueba() async {
    try {
      await _plugin.cancel(idAlarmaPrueba);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo cancelar la alarma de prueba: $e');
      }
    } finally {
      await _olvidarProgramacion(idAlarmaPrueba);
    }
  }

  /// Id reproducible de la alarma de un tratamiento para una combinación
  /// concreta de hora y día.
  ///
  /// Fórmula: `hashEstable("<tratamientoId>|<hora>|<dia>")`, acotado a 31 bits
  /// para caber en el entero de 32 bits que exige el plugin. El separador `|`
  /// desambigua los campos: dos ternas distintas solo podrían dar el mismo id
  /// si algún campo contuviera `|`, y eso no ocurre en la práctica (las horas
  /// son `HH:mm` y los ids de Firestore son alfanuméricos).
  ///
  /// Al ser determinista, el id se puede **recalcular** más tarde —al editar o
  /// borrar el tratamiento— y cancelar esa alarma concreta sin guardar el id
  /// en Firestore ni en preferencias. Eso es lo que permite
  /// [cancelarAlarmasDeTratamiento].
  ///
  /// [dia] es el día ISO: 1 = lunes … 7 = domingo, la misma convención que
  /// `HorarioDia.dias`.
  static int idDeAlarma(String tratamientoId, String hora, int dia) {
    // El 0 se reserva y se resuelve dentro de [hashEstable].
    return hashEstable('$tratamientoId|$hora|$dia');
  }

  /// Id estable de una alarma puntual de la ventana móvil.
  ///
  /// Incluye tratamiento, fecha y hora, así que se puede recalcular al
  /// confirmar, posponer o cancelar una ocurrencia concreta. El subrango
  /// negativo está reservado en [VentanaAlarmas] y no choca con los ids de la
  /// alarma semanal antigua ni con los avisos/tardíos.
  static int idDeAlarmaPuntual(String tratamientoId, DateTime horaProgramada) {
    return VentanaAlarmas.idDeOcurrencia(tratamientoId, horaProgramada);
  }

  // -----------------------------------------------------------------------
  // Ids de las notificaciones locales del paciente
  // -----------------------------------------------------------------------
  //
  // La alarma principal semanal antigua usaba ids positivos en todo el rango
  // [1, 0x7FFFFFFF]. Las alarmas puntuales de la ventana usan un subrango
  // negativo propio, y los demás tipos también, así que no chocan entre sí:
  //
  //   aviso previo:          [-0x0FFFFFFF, -1]
  //   felicitación:          [-0x1FFFFFFF, -0x10000000]
  //   tardío recurrente:     [-0x27FFFFFF, -0x20000000]
  //   tardío puntual (posponer): [-0x2FFFFFFF, -0x28000000]
  //   alarma puntual (ventana):  [-0x3FFFFFFF, -0x30000000]
  //
  // El tardío puntual es una variante del tercer tipo (mismo canal), pero con
  // subrango propio para poder cancelarlo sin tumbar el recordatorio semanal.

  static const int minIdAvisoPrevio = -0x0FFFFFFF;
  static const int maxIdAvisoPrevio = -1;
  static const int minIdFelicitacion = -0x1FFFFFFF;
  static const int maxIdFelicitacion = -0x10000000;
  static const int minIdRecordatorioTardio = -0x27FFFFFF;
  static const int maxIdRecordatorioTardio = -0x20000000;
  static const int minIdRecordatorioTardioPospuesto = -0x2FFFFFFF;
  static const int maxIdRecordatorioTardioPospuesto = -0x28000000;

  static int _idEnRango(String clave, int base, int tamano) {
    return -(base + (hashEstable(clave) % tamano));
  }

  /// Id estable del aviso 5 minutos antes de una toma.
  static int idDeAvisoPrevio(String tratamientoId, String hora, int dia) {
    return _idEnRango('aviso|$tratamientoId|$hora|$dia', 1, 0x0FFFFFFF);
  }

  /// Id estable de la felicitación de una ranura concreta.
  static int idDeFelicitacion(String tratamientoId, DateTime horaProgramada) {
    return _idEnRango(
      'felicitacion|$tratamientoId|${_claveMinuto(horaProgramada)}',
      0x10000000,
      0x10000000,
    );
  }

  /// Id estable del recordatorio tardío semanal de una toma.
  static int idDeRecordatorioTardio(
    String tratamientoId,
    String hora,
    int dia,
  ) {
    return _idEnRango(
      'tardio|$tratamientoId|$hora|$dia',
      0x20000000,
      0x08000000,
    );
  }

  /// Id estable del recordatorio tardío puntual que se crea al posponer.
  static int idDeRecordatorioTardioPospuesto(
    String tratamientoId,
    DateTime horaProgramada,
  ) {
    return _idEnRango(
      'tardio-pospuesto|$tratamientoId|${_claveMinuto(horaProgramada)}',
      0x28000000,
      0x08000000,
    );
  }

  static String _claveMinuto(DateTime fecha) {
    final y = fecha.year.toString().padLeft(4, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final d = fecha.day.toString().padLeft(2, '0');
    final h = fecha.hour.toString().padLeft(2, '0');
    final min = fecha.minute.toString().padLeft(2, '0');
    return '$y-$m-$d-$h-$min';
  }

  /// Desplaza una hora `HH:mm` y su día ISO, admitiendo cruces de medianoche.
  ///
  /// Por ejemplo, el aviso de una toma del lunes a las 00:03 es el domingo a
  /// las 23:58 (día 7), y el recordatorio tardío de una toma del domingo a las
  /// 23:55 es el lunes a las 00:10 (día 1). Se usa para que
  /// `DateTimeComponents.dayOfWeekAndTime` repita en el día correcto.
  static (String, int) desplazarHoraYDia(String hora, int dia, int minutos) {
    final partes = hora.split(':');
    final h = int.parse(partes[0]);
    final m = int.parse(partes[1]);
    var total = h * 60 + m + minutos;
    var offsetDias = 0;
    while (total < 0) {
      total += 1440;
      offsetDias--;
    }
    while (total >= 1440) {
      total -= 1440;
      offsetDias++;
    }
    final nuevoDia = ((dia - 1 + offsetDias) % 7 + 7) % 7 + 1;
    final nuevaHora =
        '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
    return (nuevaHora, nuevoDia);
  }

  /// Programa la ventana móvil de alarmas puntuales de [horario].
  ///
  /// Cada ocurrencia de los próximos [VentanaAlarmas.diasVentana] días se
  /// agenda por separado con `AndroidScheduleMode.alarmClock` y **sin**
  /// `matchDateTimeComponents`: es una alarma de reloj de una sola ejecución,
  /// no una notificación semanal recurrente. Así no depende de que el receptor
  /// del plugin rearme la siguiente repetición.
  ///
  /// Antes de programar se cancelan las alarmas puntuales futuras de este
  /// horario y las alarmas semanales antiguas de sus días, para que una
  /// reprogramación no deje dos alarmas para la misma toma.
  ///
  /// El payload mantiene el formato `tratamientoId|hora` que ya usa el resto de
  /// la app. El id de la ocurrencia sí incluye la fecha.
  Future<int> programarAlarmasDeHorario({
    required String tratamientoId,
    required HorarioDia horario,
    required String nombreMedicamento,
    DateTime? fechaInicio,
    int? duracionDias,
    DateTime? ahora,
  }) async {
    final referencia = ahora ?? DateTime.now();

    // Limpia la alarma semanal antigua de este horario (ids positivos) y las
    // alarmas puntuales futuras que ya estuvieran programadas.
    for (final dia in horario.dias) {
      final idViejo = idDeAlarma(tratamientoId, horario.hora, dia);
      await _plugin.cancel(idViejo);
      await _olvidarProgramacion(idViejo);
    }
    final futuras = VentanaAlarmas.ocurrencias(
      tratamientoId: tratamientoId,
      horarios: [horario],
      ahora: referencia,
      respetarVigencia: false,
    );
    for (final ocurrencia in futuras) {
      await _plugin.cancel(ocurrencia.id);
      await _olvidarProgramacion(ocurrencia.id);
    }

    final ocurrencias = VentanaAlarmas.ocurrencias(
      tratamientoId: tratamientoId,
      horarios: [horario],
      ahora: referencia,
      fechaInicio: fechaInicio,
      duracionDias: duracionDias,
    );
    for (final ocurrencia in ocurrencias) {
      final cuando = tz.TZDateTime.from(ocurrencia.horaProgramada, tz.local);
      await _plugin.zonedSchedule(
        ocurrencia.id,
        'Hora de tu medicina',
        '$nombreMedicamento - Hora de tomarla',
        cuando,
        const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        payload: '$tratamientoId|${ocurrencia.hora}',
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      await _guardarProgramacion(
        id: ocurrencia.id,
        tipo: 'principal_puntual',
        tratamientoId: tratamientoId,
        hora: ocurrencia.hora,
        dia: ocurrencia.horaProgramada.weekday,
        modo: AndroidScheduleMode.alarmClock,
        proxima: ocurrencia.horaProgramada,
        semanal: false,
      );
    }
    return ocurrencias.length;
  }

  /// Próxima fecha local en que ese día de la semana cae a esa hora.
  ///
  /// `dayOfWeekAndTime` solo puede fijar **un** día de la semana por alarma
  /// (el plugin avanza días hasta que el weekday de la fecha coincide con el
  /// de la fecha programada), de ahí una alarma por día en
  /// [programarAlarmasDeHorario].
  tz.TZDateTime _proximaInstanciaSemanal(String hora, int dia) {
    final partes = hora.split(':');
    final ahora = tz.TZDateTime.now(tz.local);
    var cuando = tz.TZDateTime(
      tz.local,
      ahora.year,
      ahora.month,
      ahora.day,
      int.parse(partes[0]),
      int.parse(partes[1]),
    );
    // Avanza hasta el próximo [dia]; hoy mismo sirve si la hora aún no pasó.
    while (cuando.weekday != dia || !cuando.isAfter(ahora)) {
      cuando = cuando.add(const Duration(days: 1));
    }
    return cuando;
  }

  /// Como [_proximaInstanciaSemanal], pero salta la ocurrencia actual.
  ///
  /// Se usa al confirmar o posponer una toma: el recordatorio tardío de esa
  /// ranura se cancela y se vuelve a programar para la semana siguiente, sin
  /// perder las repeticiones futuras. [despuesDe] suele ser la hora del
  /// recordatorio tardío que se está consumiendo.
  tz.TZDateTime _proximaInstanciaSemanalDesde(
    String hora,
    int dia,
    DateTime despuesDe,
  ) {
    final partes = hora.split(':');
    final ahora = tz.TZDateTime.now(tz.local);
    final referencia = despuesDe.isAfter(ahora)
        ? tz.TZDateTime.from(despuesDe, tz.local)
        : ahora;
    var cuando = tz.TZDateTime(
      tz.local,
      referencia.year,
      referencia.month,
      referencia.day,
      int.parse(partes[0]),
      int.parse(partes[1]),
    );
    while (cuando.weekday != dia || !cuando.isAfter(referencia)) {
      cuando = cuando.add(const Duration(days: 1));
    }
    return cuando;
  }

  /// Programa los tres tipos de notificación local de un horario:
  /// alarma principal (ventana puntual), aviso previo y recordatorio tardío.
  ///
  /// La felicitación no se programa: se muestra justo al confirmar.
  Future<void> programarNotificacionesDeHorario({
    required String tratamientoId,
    required HorarioDia horario,
    required String nombreMedicamento,
    DateTime? fechaInicio,
    int? duracionDias,
    DateTime? ahora,
  }) async {
    await programarAlarmasDeHorario(
      tratamientoId: tratamientoId,
      horario: horario,
      nombreMedicamento: nombreMedicamento,
      fechaInicio: fechaInicio,
      duracionDias: duracionDias,
      ahora: ahora,
    );
    await programarAvisosYRecordatoriosDeHorario(
      tratamientoId: tratamientoId,
      horario: horario,
      nombreMedicamento: nombreMedicamento,
    );
  }

  /// Programa solo el aviso previo y el recordatorio tardío de [horario].
  ///
  /// Se separa de [programarNotificacionesDeHorario] para que el editor de
  /// tratamientos pueda rearmar la ventana de alarmas puntuales de una sola vez
  /// con [rearmarAlarmasDeTratamientos] sin duplicar la alarma principal.
  Future<void> programarAvisosYRecordatoriosDeHorario({
    required String tratamientoId,
    required HorarioDia horario,
    required String nombreMedicamento,
  }) async {
    await programarAvisoPrevioDeHorario(
      tratamientoId: tratamientoId,
      horario: horario,
      nombreMedicamento: nombreMedicamento,
    );
    await programarRecordatorioTardioDeHorario(
      tratamientoId: tratamientoId,
      horario: horario,
      nombreMedicamento: nombreMedicamento,
    );
  }

  /// Rearma la ventana móvil de alarmas puntuales de [tratamientos].
  ///
  /// Cancela primero las alarmas puntuales y semanales antiguas de cada
  /// tratamiento y después agenda las ocurrencias de los próximos 7 días que
  /// caigan dentro de su vigencia. Devuelve cuántas alarmas puntuales quedaron
  /// programadas y registra el rearme para la pantalla de diagnóstico.
  ///
  /// Los avisos previos y recordatorios tardíos no se tocan aquí: siguen siendo
  /// notificaciones semanales independientes.
  Future<int> rearmarAlarmasDeTratamientos({
    required List<Tratamiento> tratamientos,
    DateTime? ahora,
  }) async {
    final referencia = ahora ?? DateTime.now();
    var cantidad = 0;

    for (final tratamiento in tratamientos) {
      await cancelarAlarmasDeTratamiento(
        tratamientoId: tratamiento.id,
        horarios: tratamiento.horarios,
        ahora: referencia,
        incluirPosponer: false,
      );
      if (!VigenciaTratamiento.estaVigente(tratamiento, referencia)) {
        continue;
      }
      for (final horario in tratamiento.horarios) {
        cantidad += await programarAlarmasDeHorario(
          tratamientoId: tratamiento.id,
          horario: horario,
          nombreMedicamento: tratamiento.nombreMedicamento,
          fechaInicio: tratamiento.fechaInicio,
          duracionDias: tratamiento.duracionDias,
          ahora: referencia,
        );
      }
    }

    await DiagnosticoService().registrarRearme(
      cantidad: cantidad,
      tratamientos: tratamientos.length,
    );
    return cantidad;
  }

  /// Aviso suave 5 minutos antes de cada toma.
  ///
  /// La hora y el día se desplazan juntos para que un aviso que cae en el día
  /// anterior (p. ej. una toma del lunes a las 00:03) siga repitiéndose el
  /// domingo a las 23:58 y no el lunes a las 23:58.
  Future<void> programarAvisoPrevioDeHorario({
    required String tratamientoId,
    required HorarioDia horario,
    required String nombreMedicamento,
  }) async {
    for (final dia in horario.dias) {
      final (horaAviso, diaAviso) = desplazarHoraYDia(horario.hora, dia, -5);
      final id = idDeAvisoPrevio(tratamientoId, horario.hora, dia);
      final cuando = _proximaInstanciaSemanal(horaAviso, diaAviso);
      await _plugin.zonedSchedule(
        id,
        'Tu medicina se acerca',
        '$nombreMedicamento a las ${horario.hora}. Ve preparando tu dosis.',
        cuando,
        const NotificationDetails(
          android: _canalAvisoPrevio,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      await _guardarProgramacion(
        id: id,
        tipo: 'aviso_previo',
        tratamientoId: tratamientoId,
        hora: horaAviso,
        dia: diaAviso,
        modo: AndroidScheduleMode.exactAllowWhileIdle,
        proxima: cuando,
        semanal: true,
      );
    }
  }

  /// Recordatorio tardío semanal: 15 minutos después de cada toma.
  Future<void> programarRecordatorioTardioDeHorario({
    required String tratamientoId,
    required HorarioDia horario,
    required String nombreMedicamento,
  }) async {
    for (final dia in horario.dias) {
      await _programarRecordatorioTardioDia(
        tratamientoId: tratamientoId,
        horaOriginal: horario.hora,
        dia: dia,
        nombreMedicamento: nombreMedicamento,
      );
    }
  }

  Future<void> _programarRecordatorioTardioDia({
    required String tratamientoId,
    required String horaOriginal,
    required int dia,
    required String nombreMedicamento,
    DateTime? despuesDe,
  }) async {
    final (horaTardio, diaTardio) = desplazarHoraYDia(horaOriginal, dia, 15);
    final cuando = despuesDe == null
        ? _proximaInstanciaSemanal(horaTardio, diaTardio)
        : _proximaInstanciaSemanalDesde(horaTardio, diaTardio, despuesDe);
    final id = idDeRecordatorioTardio(tratamientoId, horaOriginal, dia);
    await _plugin.zonedSchedule(
      id,
      '¿Ya tomaste tu medicina?',
      '$nombreMedicamento de las $horaOriginal sigue esperando. '
          'Tómala y marca YA.',
      cuando,
      const NotificationDetails(
        android: _canalRecordatorioTardio,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: _payloadRecordatorio(tratamientoId),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
    await _guardarProgramacion(
      id: id,
      tipo: 'recordatorio_tardio',
      tratamientoId: tratamientoId,
      hora: horaTardio,
      dia: diaTardio,
      modo: AndroidScheduleMode.exactAllowWhileIdle,
      proxima: cuando,
      semanal: true,
    );
  }

  /// Recordatorio tardío puntual que se reprograma al posponer una toma.
  ///
  /// Es una sola ejecución: no repite semanalmente. El semanal se conserva
  /// aparte (ver [cancelarRecordatorioTardioDeRanura]).
  Future<void> programarRecordatorioTardioPuntual({
    required String tratamientoId,
    required DateTime horaProgramada,
    required String nombreMedicamento,
  }) async {
    try {
      final cuando = tz.TZDateTime.from(
        horaProgramada.add(const Duration(minutes: 15)),
        tz.local,
      );
      if (!cuando.isAfter(tz.TZDateTime.now(tz.local))) return;
      final hora =
          '${horaProgramada.hour.toString().padLeft(2, '0')}:'
          '${horaProgramada.minute.toString().padLeft(2, '0')}';
      final id = idDeRecordatorioTardioPospuesto(tratamientoId, horaProgramada);
      await _plugin.zonedSchedule(
        id,
        '¿Ya tomaste tu medicina?',
        '$nombreMedicamento de las $hora sigue esperando. '
            'Tómala y marca YA.',
        cuando,
        const NotificationDetails(
          android: _canalRecordatorioTardio,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: _payloadRecordatorio(tratamientoId),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      await _guardarProgramacion(
        id: id,
        tipo: 'recordatorio_tardio_puntual',
        tratamientoId: tratamientoId,
        hora: hora,
        dia: cuando.weekday,
        modo: AndroidScheduleMode.exactAllowWhileIdle,
        proxima: cuando,
        semanal: false,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo programar el recordatorio tardío puntual: $e');
      }
    }
  }

  /// Cancela el recordatorio tardío de una ranura y conserva los futuros.
  ///
  /// Si la ranura pertenece a un horario semanal, se cancela el recordatorio
  /// actual y se vuelve a programar para la semana siguiente. Si es una ranura
  /// pospuesta, solo se cancela su recordatorio puntual.
  Future<void> cancelarRecordatorioTardioDeRanura({
    required String tratamientoId,
    required DateTime horaProgramada,
    required List<HorarioDia> horarios,
    required String nombreMedicamento,
  }) async {
    try {
      final idPospuesto = idDeRecordatorioTardioPospuesto(
        tratamientoId,
        horaProgramada,
      );
      await _plugin.cancel(idPospuesto);
      await _olvidarProgramacion(idPospuesto);

      final hora =
          '${horaProgramada.hour.toString().padLeft(2, '0')}:'
          '${horaProgramada.minute.toString().padLeft(2, '0')}';
      final dia = horaProgramada.weekday;
      HorarioDia? horario;
      for (final h in horarios) {
        if (h.hora == hora && h.dias.contains(dia)) {
          horario = h;
          break;
        }
      }
      if (horario == null) return;

      final idSemanal = idDeRecordatorioTardio(
        tratamientoId,
        horario.hora,
        dia,
      );
      await _plugin.cancel(idSemanal);
      await _olvidarProgramacion(idSemanal);
      await _programarRecordatorioTardioDia(
        tratamientoId: tratamientoId,
        horaOriginal: horario.hora,
        dia: dia,
        nombreMedicamento: nombreMedicamento,
        despuesDe: horaProgramada.add(const Duration(minutes: 15)),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo cancelar el recordatorio tardío: $e');
      }
    }
  }

  /// Felicitación inmediata al confirmar una toma.
  Future<void> mostrarFelicitacion({
    required String tratamientoId,
    required DateTime horaProgramada,
  }) async {
    try {
      await _plugin.show(
        idDeFelicitacion(tratamientoId, horaProgramada),
        '¡Bien hecho!',
        'Toma registrada. Sigue así.',
        const NotificationDetails(
          android: _canalFelicitaciones,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: false,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo mostrar la felicitación: $e');
      }
    }
  }

  String _payloadRecordatorio(String tratamientoId) =>
      '$_prefijoPayloadRecordatorio$tratamientoId';

  /// Guarda metadatos best-effort para la pantalla de diagnóstico. No debe
  /// romper la programación real si falla el almacenamiento local.
  Future<void> _guardarProgramacion({
    required int id,
    required String tipo,
    required AndroidScheduleMode modo,
    String? tratamientoId,
    String? hora,
    int? dia,
    DateTime? proxima,
    bool semanal = false,
  }) async {
    await DiagnosticoService().guardarProgramacion(
      ProgramacionAlarma(
        id: id,
        tipo: tipo,
        tratamientoId: tratamientoId,
        hora: hora,
        dia: dia,
        modo: modo.name,
        proxima: proxima,
        semanal: semanal,
      ),
    );
  }

  Future<void> _olvidarProgramacion(int id) async {
    await DiagnosticoService().eliminarProgramacion(id);
  }

  /// Cancela la alarma puntual de una ocurrencia concreta y la notificación
  /// que la abrió, sin tocar las demás ocurrencias de la ventana.
  ///
  /// También limpia la alarma semanal antigua del mismo horario/día y los ids
  /// de versiones anteriores, para que una instalación que venía de la versión
  /// recurrente no deje una segunda alarma sonando.
  Future<void> cancelarAlarmaDeOcurrencia({
    required String tratamientoId,
    required DateTime horaProgramada,
    required List<HorarioDia> horarios,
    int? idNotificacion,
  }) async {
    final ids = <int>{};
    if (idNotificacion != null && idNotificacion != 0) {
      // Si la alarma se abrió desde la notificación, ese id identifica la
      // ocurrencia exacta aunque el toque ocurra después de medianoche.
      ids.add(idNotificacion);
    } else {
      // Abierta desde la pantalla del paciente: la ocurrencia es la de hoy.
      ids.add(idDeAlarmaPuntual(tratamientoId, horaProgramada));

      final hora =
          '${horaProgramada.hour.toString().padLeft(2, '0')}:'
          '${horaProgramada.minute.toString().padLeft(2, '0')}';
      final dia = horaProgramada.weekday;
      for (var i = 0; i < horarios.length; i++) {
        final horario = horarios[i];
        if (horario.hora != hora) continue;
        if (horario.dias.contains(dia)) {
          ids.add(idDeAlarma(tratamientoId, horario.hora, dia));
        }
        final idAntiguo = (tratamientoId.hashCode ^ i) & 0x7FFFFFFF;
        if (idAntiguo >= 1) ids.add(idAntiguo);
      }
    }

    for (final id in ids) {
      await _plugin.cancel(id);
      await _olvidarProgramacion(id);
    }
  }

  /// Cancela las alarmas y los tres tipos de notificación local de un
  /// tratamiento. Se usa al editarlo o borrarlo.
  Future<void> cancelarNotificacionesDeTratamiento({
    required String tratamientoId,
    required List<HorarioDia> horarios,
    DateTime? ahora,
  }) async {
    await cancelarAlarmasDeTratamiento(
      tratamientoId: tratamientoId,
      horarios: horarios,
      ahora: ahora,
    );

    final ids = <int>{};
    for (final h in horarios) {
      for (final dia in h.dias) {
        ids.add(idDeAvisoPrevio(tratamientoId, h.hora, dia));
        ids.add(idDeRecordatorioTardio(tratamientoId, h.hora, dia));
      }
    }
    for (final id in ids) {
      await _plugin.cancel(id);
      await _olvidarProgramacion(id);
    }

    // Los recordatorios puntuales de posponer llevan la hora exacta en el id,
    // así que no se pueden recalcular. Se localizan por su payload.
    final payload = _payloadRecordatorio(tratamientoId);
    try {
      final pendientes = await _plugin.pendingNotificationRequests();
      for (final p in pendientes) {
        if (p.payload == payload) {
          await _plugin.cancel(p.id);
          await _olvidarProgramacion(p.id);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'No se pudieron cancelar los recordatorios tardíos puntuales: $e',
        );
      }
    }
  }

  /// Cancela todas las alarmas conocidas de un tratamiento, para no dejar
  /// alarmas huérfanas sonando al editarlo o borrarlo.
  ///
  /// Como los ids son reproducibles ([idDeAlarma]) no hace falta registrar
  /// cuáles estaban programadas: se recalculan a partir de [horarios], que
  /// deben ser los horarios **anteriores** al guardado.
  ///
  /// Además de los ids actuales se cubren los de la versión previa del código,
  /// que derivaba el id del índice del horario (`(id.hashCode ^ i) &
  /// 0x7FFFFFFF`): en los dispositivos que ya tenían instalada esa versión esas
  /// alarmas siguen vivas bajo ids que este código ya no volvería a generar.
  /// Se cubren:
  ///  - las alarmas puntuales futuras de la ventana (ids negativos),
  ///  - una alarma semanal antigua por (hora, día) de cada horario, y
  ///  - la alarma de posponer ("Recordar"), que usa un id propio por
  ///    tratamiento: `(id.hashCode & 0x7FFFFFFF) + 1`.
  Future<void> cancelarAlarmasDeTratamiento({
    required String tratamientoId,
    required List<HorarioDia> horarios,
    DateTime? ahora,
    bool incluirPosponer = true,
  }) async {
    final ids = <int>{};

    // Las ocurrencias puntuales se cancelan sin mirar la vigencia: los
    // parámetros del tratamiento pudieron cambiar desde que se programaron.
    ids.addAll(
      VentanaAlarmas.idsDeOcurrencias(
        tratamientoId: tratamientoId,
        horarios: horarios,
        ahora: ahora ?? DateTime.now(),
        respetarVigencia: false,
      ),
    );

    for (final h in horarios) {
      for (final dia in h.dias) {
        ids.add(idDeAlarma(tratamientoId, h.hora, dia));
      }
    }
    for (var i = 0; i < horarios.length; i++) {
      final idAntiguo = (tratamientoId.hashCode ^ i) & 0x7FFFFFFF;
      if (idAntiguo >= 1) ids.add(idAntiguo);
    }
    // El rearme periódico no debe cancelar una alarma de "Recordar" pendiente:
    // es una ocurrencia futura que el paciente pidió conservar.
    if (incluirPosponer) {
      ids.add((tratamientoId.hashCode & 0x7FFFFFFF) + 1);
    }

    for (final id in ids) {
      await _plugin.cancel(id);
      await _olvidarProgramacion(id);
    }
  }

  /// Cancela todas las alarmas locales (p. ej. al desvincular o editar).
  Future<void> cancelarTodas() async {
    await _plugin.cancelAll();
    await DiagnosticoService().limpiarProgramaciones();
  }

  /// Muestra una notificación local inmediata (para el cuidador).
  ///
  /// Funciona con la app en primer plano o en segundo plano (pausada), ya que
  /// el plugin muestra la notificación desde el OS. No funciona si la app fue
  /// cerrada por completo (eso requeriría FCM/un servidor).
  Future<void> mostrarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
  }) async {
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      const NotificationDetails(
        android: _canalCuidador,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }
}
