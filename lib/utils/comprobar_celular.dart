/// Lógica pura de la pantalla "Comprobar mi celular".
///
/// No depende de Flutter, del plugin de notificaciones ni de Android: recibe
/// datos ya leídos por los canales nativos. Así se puede probar sin dispositivo
/// (qué puntos existen en cada versión de Android y qué guía mostrar según la
/// marca) sin tocar Firestore.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Puntos de la lista de verificación que puede tener la pantalla.
enum PuntoCelular {
  notificaciones,
  alarmasExactas,
  pantallaCompleta,
  bateria,
  detallesApp,
}

extension PuntoCelularTexto on PuntoCelular {
  String get titulo => switch (this) {
    PuntoCelular.notificaciones => 'Notificaciones permitidas',
    PuntoCelular.alarmasExactas => 'Alarmas exactas',
    PuntoCelular.pantallaCompleta => 'Notificaciones a pantalla completa',
    PuntoCelular.bateria => 'Optimización de batería',
    PuntoCelular.detallesApp => 'Detalles de la app',
  };

  String get descripcion => switch (this) {
    PuntoCelular.notificaciones =>
      'Sin este permiso no verás los avisos de tus tomas.',
    PuntoCelular.alarmasExactas =>
      'Ayuda a que la alarma suene a la hora exacta que programaste.',
    PuntoCelular.pantallaCompleta =>
      'Permite que la alarma se abra aunque el teléfono esté bloqueado.',
    PuntoCelular.bateria =>
      'Evita que Android retrase las alarmas para ahorrar batería.',
    PuntoCelular.detallesApp =>
      'Revisa los permisos, la versión y los datos de MediPlan.',
  };

  String get etiquetaBoton => switch (this) {
    PuntoCelular.notificaciones => 'Abrir notificaciones',
    PuntoCelular.alarmasExactas => 'Abrir alarmas exactas',
    PuntoCelular.pantallaCompleta => 'Abrir pantalla completa',
    PuntoCelular.bateria => 'Abrir batería',
    PuntoCelular.detallesApp => 'Abrir detalles',
  };
}

/// Puntos que tienen sentido en una versión concreta de Android.
///
/// - Alarmas exactas existen desde Android 12 (API 31).
/// - Pantalla completa existe desde Android 14 (API 34).
/// - La optimización de batería existe desde Android 6 (API 23).
///
/// En Android 9 o inferior se ocultan los dos primeros, que no existen allí.
/// Si no se pudo leer la versión, solo se muestran los puntos universales.
List<PuntoCelular> puntosCelularParaSdk(int? sdkInt) {
  final puntos = <PuntoCelular>[PuntoCelular.notificaciones];
  if (sdkInt != null && sdkInt >= 31) {
    puntos.add(PuntoCelular.alarmasExactas);
  }
  if (sdkInt != null && sdkInt >= 34) {
    puntos.add(PuntoCelular.pantallaCompleta);
  }
  if (sdkInt != null && sdkInt >= 23) {
    puntos.add(PuntoCelular.bateria);
  }
  puntos.add(PuntoCelular.detallesApp);
  return puntos;
}

/// Decide si hay que mostrar el aviso amable del primer arranque.
///
/// Un `null` significa "no se pudo comprobar": no se trata como una denegación
/// para no asustar al paciente con un falso positivo.
bool faltanPermisosCriticos({
  required int? sdkInt,
  required bool? notificaciones,
  required bool? alarmasExactas,
  required bool? pantallaCompleta,
  required bool? bateriaSinRestricciones,
}) {
  if (notificaciones == false) return true;
  if (sdkInt != null && sdkInt >= 31 && alarmasExactas == false) return true;
  if (sdkInt != null && sdkInt >= 34 && pantallaCompleta == false) return true;
  if (sdkInt != null && sdkInt >= 23 && bateriaSinRestricciones == false) {
    return true;
  }
  return false;
}

/// Texto exacto que se muestra al final de la guía por fabricante.
const String notaGuiaFabricante =
    'Los nombres de los menús pueden variar según el modelo.';

/// Guía de ajustes propia de una marca.
class GuiaFabricante {
  final String nombre;
  final List<String> pasos;

  const GuiaFabricante({required this.nombre, required this.pasos});
}

const GuiaFabricante _guiaXiaomi = GuiaFabricante(
  nombre: 'Xiaomi, Redmi o POCO',
  pasos: [
    'Abre Ajustes > Aplicaciones > Administrar aplicaciones > MediPlan.',
    'Activa Inicio automático.',
    'En Ahorro de batería, elige Sin restricciones.',
    'Activa Mostrar en pantalla de bloqueo y permite las notificaciones.',
  ],
);

const GuiaFabricante _guiaSamsung = GuiaFabricante(
  nombre: 'Samsung',
  pasos: [
    'Abre Ajustes > Batería y cuidado del dispositivo > Batería.',
    'Quita MediPlan de Aplicaciones en suspensión y Aplicaciones inactivas.',
    'En Ajustes > Aplicaciones > MediPlan > Batería, elige Sin restricciones.',
    'Revisa Notificaciones y activa Mostrar en pantalla de bloqueo.',
  ],
);

const GuiaFabricante _guiaHuawei = GuiaFabricante(
  nombre: 'Huawei u Honor',
  pasos: [
    'Inicio de aplicaciones: administrar manualmente y activar inicio automático, inicio secundario y ejecución en segundo plano.',
    'Abre Ajustes > Batería > Inicio de aplicaciones y revisa MediPlan.',
    'En Ajustes > Aplicaciones > MediPlan > Batería, elige Sin restricciones.',
    'Activa Mostrar en pantalla de bloqueo y permite las notificaciones.',
    'En algunos Huawei la alarma llega como notificación y debes tocarla para '
        'abrirla. Activa el inicio manual y las ventanas emergentes para '
        'mejorarlo.',
  ],
);

const GuiaFabricante _guiaOppo = GuiaFabricante(
  nombre: 'Oppo, Realme o Vivo',
  pasos: [
    'Abre Ajustes > Batería > Optimización de batería > MediPlan > No optimizar.',
    'Activa Inicio automático y permite la ejecución en segundo plano.',
    'Revisa Notificaciones y activa Mostrar en pantalla de bloqueo.',
    'Si tu modelo lo pide, permite las ventanas emergentes en segundo plano.',
  ],
);

const GuiaFabricante _guiaMotorola = GuiaFabricante(
  nombre: 'Motorola',
  pasos: [
    'Abre Ajustes > Batería > Optimización de batería.',
    'Busca MediPlan y elige No optimizar.',
    'En Ajustes > Aplicaciones > MediPlan > Notificaciones, permite los avisos.',
    'Activa Mostrar en pantalla de bloqueo.',
  ],
);

const GuiaFabricante _guiaOtros = GuiaFabricante(
  nombre: 'Otros celulares',
  pasos: [
    'Abre Ajustes > Aplicaciones > MediPlan.',
    'En Batería, elige Sin restricciones o No optimizar.',
    'Activa Inicio automático si tu marca ofrece esa opción.',
    'Permite las notificaciones y activa Mostrar en pantalla de bloqueo.',
  ],
);

/// Elige la guía según `Build.MANUFACTURER`, sin distinguir mayúsculas.
GuiaFabricante guiaParaFabricante(String? fabricante) {
  final texto = (fabricante ?? '').toLowerCase();
  if (texto.contains('xiaomi') ||
      texto.contains('redmi') ||
      texto.contains('poco')) {
    return _guiaXiaomi;
  }
  if (texto.contains('samsung')) return _guiaSamsung;
  if (texto.contains('huawei') || texto.contains('honor')) {
    return _guiaHuawei;
  }
  if (texto.contains('oppo') ||
      texto.contains('realme') ||
      texto.contains('vivo')) {
    return _guiaOppo;
  }
  if (texto.contains('motorola') || texto.contains('moto')) {
    return _guiaMotorola;
  }
  return _guiaOtros;
}

/// Etiqueta visible del tipo de una notificación programada.
String etiquetaTipoAlarma(String? tipo) {
  return switch ((tipo ?? '').trim()) {
    'aviso_previo' => 'Aviso previo',
    'recordatorio_tardio' ||
    'recordatorio_tardio_puntual' ||
    'tardio' ||
    'tardio_puntual' ||
    'tardio_pospuesto' => 'Recordatorio',
    'prueba' => 'Alarma de prueba',
    _ => 'Alarma',
  };
}

/// Hora local compacta para la lista de alarmas programadas.
String textoHoraLocal(DateTime? fecha, DateTime ahora) {
  if (fecha == null) return 'Hora no disponible';
  final h = fecha.hour.toString().padLeft(2, '0');
  final m = fecha.minute.toString().padLeft(2, '0');
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final diferenciaDias = dia.difference(hoy).inDays;
  if (diferenciaDias == 0) return '$h:$m';
  if (diferenciaDias == 1) return 'Mañana $h:$m';
  return '${fecha.day}/${fecha.month} $h:$m';
}

/// Fecha y hora local para el último rearmado.
String textoFechaHoraLocal(DateTime? fecha) {
  if (fecha == null) return 'Todavía no';
  final h = fecha.hour.toString().padLeft(2, '0');
  final m = fecha.minute.toString().padLeft(2, '0');
  return '${fecha.day}/${fecha.month} a las $h:$m';
}

/// Descripción legible de la versión de Android.
String textoVersionAndroid(int? sdkInt, String? release) {
  final version = release?.trim() ?? '';
  if (version.isNotEmpty && sdkInt != null) {
    return 'Android $version (API $sdkInt)';
  }
  if (version.isNotEmpty) return 'Android $version';
  if (sdkInt != null) return 'Android (API $sdkInt)';
  return 'Versión de Android no disponible';
}

/// Estado de la optimización de batería para el resumen del celular.
String textoEstadoBateria(bool? sinRestricciones) {
  return switch (sinRestricciones) {
    true => 'Batería sin restricciones',
    false => 'Optimización de batería activa',
    null => 'No se pudo comprobar la batería',
  };
}

/// Reconstruye la próxima hora de una alarma a partir de su payload
/// `tratamientoId|HH:mm`.
///
/// Es solo un respaldo para alarmas programadas por versiones anteriores que no
/// tengan metadatos locales. Devuelve `null` si el payload no tiene ese formato.
DateTime? horaDesdePayloadAlarma(String? payload, DateTime ahora) {
  if (payload == null || payload.isEmpty) return null;
  final partes = payload.split('|');
  if (partes.length != 2) return null;
  final hm = partes[1].split(':');
  if (hm.length != 2) return null;
  final h = int.tryParse(hm[0]);
  final m = int.tryParse(hm[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  var fecha = DateTime(ahora.year, ahora.month, ahora.day, h, m);
  if (!fecha.isAfter(ahora)) {
    fecha = fecha.add(const Duration(days: 1));
  }
  return fecha;
}

/// Datos que la pantalla ya recolectó del dispositivo.
class EstadoCelular {
  final int? sdkInt;
  final String? fabricante;
  final String? versionAndroid;
  final bool? notificacionesPermitidas;
  final bool? alarmasExactasPermitidas;
  final bool? pantallaCompletaPermitida;
  final bool? bateriaSinRestricciones;
  final List<AlarmaEnCelular> alarmas;
  final DateTime? ultimoRearme;
  final int huerfanasCanceladasUltimoRearme;
  final String? ultimoErrorSincronizacion;

  const EstadoCelular({
    this.sdkInt,
    this.fabricante,
    this.versionAndroid,
    this.notificacionesPermitidas,
    this.alarmasExactasPermitidas,
    this.pantallaCompletaPermitida,
    this.bateriaSinRestricciones,
    this.alarmas = const [],
    this.ultimoRearme,
    this.huerfanasCanceladasUltimoRearme = 0,
    this.ultimoErrorSincronizacion,
  });

  /// `true` cuando el punto aplica y está resuelto.
  bool listo(PuntoCelular punto) {
    return switch (punto) {
      PuntoCelular.notificaciones => notificacionesPermitidas == true,
      PuntoCelular.alarmasExactas => alarmasExactasPermitidas == true,
      PuntoCelular.pantallaCompleta => pantallaCompletaPermitida == true,
      PuntoCelular.bateria => bateriaSinRestricciones == true,
      // Los detalles de la app no son un permiso: siempre se pueden abrir.
      PuntoCelular.detallesApp => true,
    };
  }
}

/// Una notificación pendiente tal como se muestra en la pantalla.
class AlarmaEnCelular {
  final String tipo;
  final DateTime? hora;
  final bool esPrueba;

  const AlarmaEnCelular({
    required this.tipo,
    required this.hora,
    this.esPrueba = false,
  });
}


/// Indica si la fila del canal de alarmas tiene sentido en esa version de
/// Android. Los canales existen desde Android 8 (API 26).
bool mostrarFilaCanalAlarmas(int? sdkInt) {
  return sdkInt != null && sdkInt >= 26;
}

/// Decide si el canal de alarmas esta en silencio o bloqueado.
bool canalAlarmasEnProblema(
  AndroidNotificationChannel? canal, {
  required bool? notificacionesHabilitadas,
}) {
  if (notificacionesHabilitadas == false) return true;
  if (canal == null) return true;
  if (canal.importance.index < Importance.high.index) return true;
  if (!canal.playSound) return true;
  if (!canal.enableVibration) return true;
  return false;
}

/// Frase en tuteo que explica el estado real del canal.
String fraseCanalAlarmas(
  AndroidNotificationChannel? canal, {
  required bool? notificacionesHabilitadas,
}) {
  if (notificacionesHabilitadas == false) {
    return 'Las notificaciones estan desactivadas para MediPlan. Activalas '
        'para que la alarma suene.';
  }
  if (canal == null) {
    return 'No se pudo leer el canal de alarmas. Revisa los ajustes.';
  }
  if (canal.importance.index < Importance.high.index ||
      !canal.playSound ||
      !canal.enableVibration) {
    return 'El canal esta en silencio o bloqueado. Abrelo y ponlo en Alta, '
        'con sonido y vibracion.';
  }
  return 'El canal esta listo: sonara y vibrara cuando toque.';
}
