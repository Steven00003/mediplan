package com.mediplan.mediplan

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CANAL_AJUSTES = "com.mediplan.mediplan/ajustes_escritura"
        const val METODO_PUEDE_ESCRIBIR = "puedeEscribirAjustes"
        const val METODO_ABRIR_AJUSTES = "abrirAjustesEscritura"
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
