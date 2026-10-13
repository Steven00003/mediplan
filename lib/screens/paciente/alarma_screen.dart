import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/push_service.dart';
import '../../services/sensores_service.dart';
import '../../theme/app_colors.dart';

/// Pantalla de alarma del Paciente.
///
/// - Muestra la foto real del medicamento, no el nombre.
/// - Brillo al máximo (con el sensor de luz detectando ambientes oscuros).
/// - Vibración fuerte y sostenida.
/// - Botón grande "YA" → confirma la toma; el cuidador la ve en tiempo real
///   (y recibe una notificación local si tiene la app en primer plano).
/// - Botón secundario "Recordar" → pospone unos minutos y vuelve a sonar.
class AlarmaScreen extends StatefulWidget {
  final Tratamiento tratamiento;
  final TimeOfDay horaProgramada;
  final String pacienteId;

  /// A partir de este atraso la toma se registra como "tardó" en vez de "tomó".
  static const Duration _plazoTardio = Duration(minutes: 15);

  const AlarmaScreen({
    super.key,
    required this.tratamiento,
    required this.horaProgramada,
    required this.pacienteId,
  });

  @override
  State<AlarmaScreen> createState() => _AlarmaScreenState();
}

class _AlarmaScreenState extends State<AlarmaScreen>
    with WidgetsBindingObserver {
  final FirestoreService _fs = FirestoreService();
  final SensoresService _sensores = SensoresService();
  final NotificacionesService _notif = NotificacionesService();
  final PushService _push = PushService();

  Timer? _vibracionTimer;
  bool _procesando = false;

  DateTime get _horaProgramada {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      widget.horaProgramada.hour,
      widget.horaProgramada.minute,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepararAlarma();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vibracionTimer?.cancel();
    _sensores.detenerVibracion();
    _sensores.restaurarBrillo();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver al primer plano, reaseguramos la vibración.
      _iniciarVibracionContinua();
      _sensores.subirBrilloAlMaximo();
    }
  }

  Future<void> _prepararAlarma() async {
    // El brillo al máximo requiere WRITE_SETTINGS en Android: si falta,
    // abrimos la pantalla del sistema para que el usuario lo active.
    await _sensores.asegurarPermisoBrillo();
    await _sensores.subirBrilloAlMaximo();
    _iniciarVibracionContinua();
  }

  void _iniciarVibracionContinua() {
    _vibracionTimer?.cancel();
    _vibracionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sensores.vibrarFuerteYContinuo();
    });
_sensores.vibrarFuerteYContinuo();
  }

  /// Confirma la toma: registra como "tomó" (o "tardó" si se pasó del plazo) y el
  /// cuidador lo ve en tiempo real en su dashboard, con una notificación local
  /// si tiene la app en primer plano.
  Future<void> _confirmar() async {
    if (_procesando) return;
    setState(() => _procesando = true);

    // Se compara contra la hora programada, no contra "ahora": si el paciente
    // estuvo en la alarma un rato, la toma sigue siendo la de las 08:00.
    //
    // El plazo es "> 15 minutos", no "> 15 minutos y pico": a los 15:00 exactos
    // la toma todavía se cuenta como "tomó". Por eso se compara la Duration
    // entera en vez de usar `inMinutes`, que trunca a 15.
    final atraso = DateTime.now().difference(_horaProgramada);
    final estado = atraso > AlarmaScreen._plazoTardio
        ? EstadoToma.tardia
        : EstadoToma.tomada;

    await _fs.crearRegistroToma(
      tratamientoId: widget.tratamiento.id,
      pacienteId: widget.pacienteId,
      horaProgramada: _horaProgramada,
      estado: estado,
    );

    // Aviso al cuidador (best effort): no se espera y no puede hacer fallar la
    // toma, que ya quedó registrada arriba.
    unawaited(_push.notificarConfirmacion(
      pacienteId: widget.pacienteId,
      nombreMedicamento: widget.tratamiento.nombreMedicamento,
      hora: _horaTxt,
      estado: estado,
    ));

    _limpiarYSalir();
  }

  /// "Recordar": registra como pospuesta y reprograma la alarma en 5 minutos.
  Future<void> _recordar() async {
    if (_procesando) return;
    setState(() => _procesando = true);

    await _fs.crearRegistroToma(
      tratamientoId: widget.tratamiento.id,
      pacienteId: widget.pacienteId,
      horaProgramada: _horaProgramada,
      estado: EstadoToma.pospuesta,
    );

    // Igual que en `_confirmar`: el push es el extra, no la fuente de verdad.
    unawaited(_push.notificarConfirmacion(
      pacienteId: widget.pacienteId,
      nombreMedicamento: widget.tratamiento.nombreMedicamento,
      hora: _horaTxt,
      estado: EstadoToma.pospuesta,
    ));

    // Reagenda una alarma local para dentro de 5 minutos.
    final dentro = DateTime.now().add(const Duration(minutes: 5));
    final hora = TimeOfDay(hour: dentro.hour, minute: dentro.minute);
    await _notif.programarAlarmaDiaria(
      id: (widget.tratamiento.id.hashCode & 0x7FFFFFFF) + 1,
      hora: '${_pad(hora.hour)}:${_pad(hora.minute)}',
      nombreMedicamento: widget.tratamiento.nombreMedicamento,
      payload: '${widget.tratamiento.id}|${_pad(hora.hour)}:${_pad(hora.minute)}',
    );

    _limpiarYSalir();
  }

  void _limpiarYSalir() {
    _vibracionTimer?.cancel();
    _sensores.detenerVibracion();
    _sensores.restaurarBrillo();
    if (mounted) Navigator.of(context).pop();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String get _horaTxt =>
      '${_pad(widget.horaProgramada.hour)}:${_pad(widget.horaProgramada.minute)}';

  @override
  Widget build(BuildContext context) {
    final t = widget.tratamiento;
    final bytesFoto =
        (t.fotoBase64 != null && t.fotoBase64!.isNotEmpty)
            ? ImagenService.decodificar(t.fotoBase64!)
            : null;
    final tieneFoto = bytesFoto != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _horaTxt,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                // Foto real del medicamento
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 260,
                    height: 260,
                    color: Colors.white,
                    child: tieneFoto
                        ? Image.memory(
                            bytesFoto,
                            width: 260,
                            height: 260,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.medication,
                                  size: 120, color: AppColors.textSecondary),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.medication,
                                size: 120, color: AppColors.textSecondary),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                // Dosis visual y simple
                Text(
                  '${t.dosis} DOSIS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${t.nombreMedicamento}\nEs hora de tomar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 40),
                // Botón grande YA
                SizedBox(
                  width: double.infinity,
                  height: 90,
                  child: ElevatedButton(
                    onPressed: _procesando ? null : _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'YA',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Botón secundario Recordar (más pequeño)
                TextButton(
                  onPressed: _procesando ? null : _recordar,
                  child: const Text(
                    'Recordar',
                    style: TextStyle(color: Colors.white54, fontSize: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
