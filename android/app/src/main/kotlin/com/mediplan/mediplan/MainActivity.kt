package com.mediplan.mediplan

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CANAL_AJUSTES = "com.mediplan.mediplan/ajustes_escritura"
        const val METODO_PUEDE_ESCRIBIR = "puedeEscribirAjustes"
        const val METODO_ABRIR_AJUSTES = "abrirAjustesEscritura"

        // Datos del sistema que Dart no expone: zona IANA, nivel de API y
        // permiso de pantalla completa.
        const val CANAL_SISTEMA = "com.mediplan.mediplan/diagnostico"
        const val METODO_SDK_INT = "androidSdkInt"
        const val METODO_FABRICANTE = "fabricante"
        const val METODO_ZONA_HORARIA = "timeZoneId"
        const val METODO_PUEDE_PANTALLA_COMPLETA = "canUseFullScreenIntent"
        const val METODO_ESTADO_ENERGIA = "estadoEnergia"
        const val METODO_ABRIR_AJUSTES_NOTIFICACIONES =
            "abrirAjustesNotificaciones"
        const val METODO_ABRIR_AJUSTES_BATERIA = "abrirAjustesBateria"
        const val METODO_ABRIR_AJUSTES_ALARMAS_EXACTAS =
            "abrirAjustesAlarmasExactas"
        const val METODO_ABRIR_DETALLES_APP = "abrirDetallesApp"

        // Flags de ventana para que la alarma se vea sobre el bloqueo.
        const val CANAL_VENTANA_ALARMA = "com.mediplan.mediplan/ventana_alarma"
        const val METODO_DESACTIVAR_FLAGS = "desactivarFlags"
        const val METODO_CANCELAR_NOTIFICACIONES = "cancelarNotificaciones"
        const val ACCION_SELECT_NOTIFICATION = "SELECT_NOTIFICATION"
        const val EXTRA_PAYLOAD = "payload"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activarFlagsDeAlarmaSiCorresponde(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        activarFlagsDeAlarmaSiCorresponde(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_AJUSTES)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METODO_PUEDE_ESCRIBIR -> result.success(puedeEscribirAjustes())
                    METODO_ABRIR_AJUSTES -> {
                        abrirAjustesEscritura()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_SISTEMA)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METODO_SDK_INT -> result.success(Build.VERSION.SDK_INT)
                    METODO_FABRICANTE -> result.success(Build.MANUFACTURER ?: "")
                    // java.util.TimeZone.getDefault().id devuelve el ID IANA
                    // real del dispositivo (p. ej. America/Bogota).
                    METODO_ZONA_HORARIA ->
                        result.success(java.util.TimeZone.getDefault().id)
                    METODO_PUEDE_PANTALLA_COMPLETA -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val manager = getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager
                            result.success(manager.canUseFullScreenIntent())
                        } else {
                            // El permiso no existe antes de Android 14.
                            result.success(true)
                        }
                    }
                    METODO_ESTADO_ENERGIA -> result.success(estadoEnergia())
                    METODO_ABRIR_AJUSTES_NOTIFICACIONES -> {
                        abrirAjustesNotificaciones()
                        result.success(null)
                    }
                    METODO_ABRIR_AJUSTES_BATERIA -> {
                        abrirAjustesBateria()
                        result.success(null)
                    }
                    METODO_ABRIR_AJUSTES_ALARMAS_EXACTAS -> {
                        abrirAjustesAlarmasExactas()
                        result.success(null)
                    }
                    METODO_ABRIR_DETALLES_APP -> {
                        abrirDetallesApp()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_VENTANA_ALARMA)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METODO_DESACTIVAR_FLAGS -> {
                        desactivarFlagsDeAlarma()
                        result.success(null)
                    }
                    METODO_CANCELAR_NOTIFICACIONES -> {
                        val ids = call.argument<List<Int>>("ids").orEmpty()
                        cancelarNotificaciones(ids)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Si la actividad se abrió desde la notificación de una alarma, permite
     * mostrarla sobre el bloqueo y enciende la pantalla. Se detecta por la
     * acción y el payload que pone flutter_local_notifications; las alertas del
     * cuidador no llevan payload y no activan estos flags.
     */
    private fun activarFlagsDeAlarmaSiCorresponde(intent: Intent?) {
        if (!esIntentoDeAlarma(intent)) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun esIntentoDeAlarma(intent: Intent?): Boolean {
        if (intent?.action != ACCION_SELECT_NOTIFICATION) return false
        return !intent.getStringExtra(EXTRA_PAYLOAD).isNullOrBlank()
    }

    private fun desactivarFlagsDeAlarma() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
    }

    /** Cancela la notificación mostrada, pero no la alarma semanal programada. */
    private fun cancelarNotificaciones(ids: List<Int>) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        for (id in ids.distinct()) {
            manager.cancel(id)
        }
    }

    /** Estado de energía, Doze y No molestar para el diagnóstico. */
    private fun estadoEnergia(): Map<String, Any?> {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val notifications = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        val alarmas = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val sdk = Build.VERSION.SDK_INT
        return mapOf(
            "sdkInt" to sdk,
            "release" to Build.VERSION.RELEASE,
            "powerSaveMode" to power.isPowerSaveMode,
            "deviceIdleMode" to
                if (sdk >= Build.VERSION_CODES.M) power.isDeviceIdleMode else false,
            "ignoringBatteryOptimizations" to
                if (sdk >= Build.VERSION_CODES.M) {
                    power.isIgnoringBatteryOptimizations(packageName)
                } else {
                    true
                },
            "interruptionFilter" to
                if (sdk >= Build.VERSION_CODES.M) {
                    notifications.currentInterruptionFilter
                } else {
                    -1
                },
            "canScheduleExactAlarms" to
                if (sdk >= Build.VERSION_CODES.S) {
                    alarmas.canScheduleExactAlarms()
                } else {
                    true
                },
        )
    }

    private fun abrirAjustesNotificaciones() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        abrirAjustes(intent)
    }

    private fun abrirAjustesBateria() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        abrirAjustes(intent)
    }

    private fun abrirDetallesApp() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun abrirAjustesAlarmasExactas() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent(
                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        abrirAjustes(intent)
    }

    private fun abrirAjustes(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
    }

    /** Equivale a Settings.System.canWrite(context): requiere WRITE_SETTINGS. */
    private fun puedeEscribirAjustes(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(this)
        } else {
            true
        }

    /**
     * Abre Ajustes → "Modificar las configuraciones del sistema" apuntando a
     * MediPlan, para que el usuario conceda WRITE_SETTINGS manualmente.
     */
    private fun abrirAjustesEscritura() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val intent = Intent(
            Settings.ACTION_MANAGE_WRITE_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
    }
}
