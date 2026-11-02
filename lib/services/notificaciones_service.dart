import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/tratamiento.dart';
import '../utils/hash_estable.dart';

/// Datos que acompañan al toque de una alarma.
///
/// [idNotificacion] es el id que Android le asignó a la notificación mostrada;
/// se usa para quitarla de la barra al confirmar o posponer sin cancelar la
/// alarma semanal que la generó.
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

  /// Canal propio para obtener la zona IANA real del dispositivo. Se usa en
  /// `inicializar()` para que `timezone` no se quede en UTC por defecto.
  static const MethodChannel _canalDiagnostico =
      MethodChannel('com.mediplan.mediplan/diagnostico');

  static const _channel = AndroidNotificationDetails(
    canalAlarmasId,
    'Alarmas de medicamentos',
    channelDescription:
        'Recordatorios de toma de medicamentos de MediPlan',
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
        _registrarPayload(
          respuesta?.payload,
          idNotificacion: respuesta?.id,
        );
      }
    } catch (e) {
      debugPrint('No se pudo leer el lanzamiento por notificación: $e');
    }

    await _crearCanales();
  }

  /// Recibe el toque de una notificación con la app ya en marcha.
  void _alRecibirRespuesta(NotificationResponse respuesta) {
    _registrarPayload(
      respuesta.payload,
      idNotificacion: respuesta.id,
    );
  }

  void _registrarPayload(String? payload, {int? idNotificacion}) {
    final limpio = payload?.trim();
    if (limpio == null || limpio.isEmpty) return;
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
      final id = await _canalDiagnostico.invokeMethod<String>('timeZoneId');
      if (id == null || id.isEmpty) return;
      tz.setLocalLocation(tz.getLocation(id));
    } catch (e) {
      // En tests o fuera de Android el canal no existe. Se mantiene el
      // comportamiento anterior (UTC) en vez de romper el arranque.
      debugPrint('No se pudo configurar la zona horaria local: $e');
    }
  }

  /// Crea los canales explícitamente.
  ///
  /// Android 8+ descarta una notificación cuyo canal no exista. Las alarmas
  /// locales lo crean al vuelo, pero las que muestra FCM con la app cerrada no:
  /// necesitan que [canalCuidadorId] exista de antemano (su id va en el
  /// AndroidManifest como `default_notification_channel_id`).
  Future<void> _crearCanales() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      canalAlarmasId,
      'Alarmas de medicamentos',
      description: 'Recordatorios de toma de medicamentos de MediPlan',
      importance: Importance.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      canalCuidadorId,
      'Alertas de tus pacientes',
      description:
          'Avisos en tiempo real de confirmaciones de tomas de tus pacientes',
      importance: Importance.high,
    ));
  }

  /// Pide permiso para mostrar notificaciones (Android 13+ / iOS).
  Future<void> pedirPermiso() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Diagnóstico temporal: alarmas que el plugin tiene registradas en el
  /// sistema. En Android lee la caché de `SharedPreferences` del plugin, así
  /// que confirma que `zonedSchedule()` llegó a guardar la solicitud, no que
  /// `AlarmManager` la haya aceptado.
  Future<List<PendingNotificationRequest>> alarmasProgramadas() =>
      _plugin.pendingNotificationRequests();

  /// Diagnóstico temporal: estado del permiso de alarmas exactas.
  ///
  /// En Android < 12 el plugin devuelve `true` porque el permiso no existe;
  /// no debe interpretarse como un permiso concedido.
  Future<bool?> puedeProgramarAlarmasExactas() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.canScheduleExactNotifications();
  }

  /// Nivel de API de Android, o `null` si el canal nativo no está disponible.
  Future<int?> androidSdkInt() async {
    try {
      return await _canalDiagnostico.invokeMethod<int>('androidSdkInt');
    } catch (_) {
      return null;
    }
  }

  /// Indica si Android permite abrir la alarma a pantalla completa.
  ///
  /// En Android < 14 el permiso no existe y el canal devuelve `true`.
  Future<bool?> puedeUsarPantallaCompleta() async {
    try {
      return await _canalDiagnostico
          .invokeMethod<bool>('canUseFullScreenIntent');
    } catch (_) {
      return null;
    }
  }

  /// Abre la pantalla de Ajustes donde se concede el permiso de pantalla
  /// completa (Android 14+). Devuelve si quedó concedido al volver.
  Future<bool?> solicitarPermisoPantallaCompleta() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.requestFullScreenIntentPermission();
  }

  /// Diagnóstico temporal: zona horaria que usa `timezone`.
  ///
  /// Si vale `UTC`, las horas `HH:mm` se están interpretando como UTC y no
  /// como hora local del dispositivo.
  String get zonaHoraria => tz.local.name;

  /// Diagnóstico temporal: hora actual en la zona que usa `timezone`.
  String get ahoraEnZonaHoraria => tz.TZDateTime.now(tz.local).toString();

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
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
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

  /// Programa una alarma por cada día de la semana en que aplica [horario].
  ///
  /// Cada día se agenda por separado con
  /// `DateTimeComponents.dayOfWeekAndTime`, con lo que el plugin **repite esa
  /// notificación cada semana, y solo en ese día**. Antes se agendaba un único
  /// `zonedSchedule` sin `matchDateTimeComponents`, que por definición suena
  /// **una sola vez** (el plugin además la saca de su caché de pendientes al
  /// dispararse), así que había que re-guardar el tratamiento cada día para
  /// que la alarma siguiera viva.
  ///
  /// Se agenda una alarma por día siempre, incluso cuando aplican los 7 (en
  /// ese caso cabría usar `DateTimeComponents.time` con una sola alarma), para
  /// que el número de alarmas pendientes sea siempre igual al número de
  /// entradas de `horarios` y no haya un caso especial que se desincronice.
  ///
  /// El [payload] mantiene el formato `tratamientoId|hora` que ya usa el resto
  /// de la app; no incluye el día porque quien lo recibe no lo necesita para
  /// resolver la toma.
  Future<void> programarAlarmasDeHorario({
    required String tratamientoId,
    required HorarioDia horario,
    required String nombreMedicamento,
  }) async {
    for (final dia in horario.dias) {
      await _plugin.zonedSchedule(
        idDeAlarma(tratamientoId, horario.hora, dia),
        'Hora de tu medicina',
        '$nombreMedicamento - Hora de tomarla',
        _proximaInstanciaSemanal(horario.hora, dia),
        const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '$tratamientoId|${horario.hora}',
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
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
    var cuando = tz.TZDateTime(tz.local, ahora.year, ahora.month, ahora.day,
        int.parse(partes[0]), int.parse(partes[1]));
    // Avanza hasta el próximo [dia]; hoy mismo sirve si la hora aún no pasó.
    while (cuando.weekday != dia || !cuando.isAfter(ahora)) {
      cuando = cuando.add(const Duration(days: 1));
    }
    return cuando;
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
  ///  - una alarma por (hora, día) de cada horario, y
  ///  - la alarma de posponer ("Recordar"), que usa un id propio por
  ///    tratamiento: `(id.hashCode & 0x7FFFFFFF) + 1`.
  Future<void> cancelarAlarmasDeTratamiento({
    required String tratamientoId,
    required List<HorarioDia> horarios,
  }) async {
    final ids = <int>{};

    for (final h in horarios) {
      for (final dia in h.dias) {
        ids.add(idDeAlarma(tratamientoId, h.hora, dia));
      }
    }
    for (var i = 0; i < horarios.length; i++) {
      final idAntiguo = (tratamientoId.hashCode ^ i) & 0x7FFFFFFF;
      if (idAntiguo >= 1) ids.add(idAntiguo);
    }
    ids.add((tratamientoId.hashCode & 0x7FFFFFFF) + 1);

    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }

  /// Cancela todas las alarmas locales (p. ej. al desvincular o editar).
  Future<void> cancelarTodas() async {
    await _plugin.cancelAll();
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
