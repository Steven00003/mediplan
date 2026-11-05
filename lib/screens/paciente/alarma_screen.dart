import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/sensores_service.dart';
import '../../services/ventana_alarma_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/etiqueta_toma.dart';
import '../../utils/proxima_toma.dart';
import '../../utils/vigencia_tratamiento.dart';

/// Pantalla de alarma del Paciente.
///
/// - Muestra la foto real del medicamento, no el nombre.
/// - Brillo al máximo (con el sensor de luz detectando ambientes oscuros).
/// - Vibración fuerte y sostenida.
/// - Botón grande "YA" → confirma la toma, cancela el recordatorio tardío y
///   muestra una felicitación local.
/// - Botón secundario "Recordar" → pospone unos minutos, reprograma el
///   recordatorio tardío con el nuevo desfase y vuelve a sonar.
class AlarmaScreen extends StatefulWidget {
  final Tratamiento tratamiento;
  final TimeOfDay horaProgramada;
  final String pacienteId;

  /// Id de la notificación que abrió esta alarma, si vino de un toque.
  final int? idNotificacion;

  /// A partir de este atraso la toma se registra como "tardó" en vez de "tomó".
  static const Duration _plazoTardio = Duration(minutes: 15);

  const AlarmaScreen({
    super.key,
    required this.tratamiento,
    required this.horaProgramada,
    required this.pacienteId,
    this.idNotificacion,
  });

  @override
  State<AlarmaScreen> createState() => _AlarmaScreenState();
}

class _AlarmaScreenState extends State<AlarmaScreen>
    with WidgetsBindingObserver {
  final FirestoreService _fs = FirestoreService();
  final SensoresService _sensores = SensoresService();
  final NotificacionesService _notif = NotificacionesService();
  final VentanaAlarmaService _ventana = const VentanaAlarmaService();

  Timer? _vibracionTimer;
  Timer? _relojTimer;
  bool _procesando = false;
  bool _flagsVentanaDesactivados = false;
  bool _mostrarPistaScroll = true;
  final ScrollController _scrollController = ScrollController();
  late final Future<List<RegistroToma>> _historialFuturo;
  late final Uint8List? _bytesFoto;

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
    _scrollController.addListener(_alDesplazar);
    _relojTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
    _historialFuturo = _fs
        .getHistorialDeTratamiento(widget.pacienteId, widget.tratamiento.id)
        .timeout(const Duration(seconds: 8));
    // Se decodifica una sola vez: el reloj de la cuenta regresiva reconstruye
    // la pantalla cada segundo y no debe volver a decodificar la foto.
    final foto = widget.tratamiento.fotoBase64;
    _bytesFoto = (foto != null && foto.isNotEmpty)
        ? ImagenService.decodificar(foto)
        : null;
    _prepararAlarma();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vibracionTimer?.cancel();
    _relojTimer?.cancel();
    _scrollController
      ..removeListener(_alDesplazar)
      ..dispose();
    _sensores.detenerVibracion();
    _sensores.restaurarBrillo();
    // También cubre la salida con el botón Atrás, que no pasa por
    // `_limpiarYSalir`.
    unawaited(_desactivarFlagsVentana());
    super.dispose();
  }

  void _alDesplazar() {
    if (!_scrollController.hasClients) return;
    final mostrar = _scrollController.offset < 24;
    if (mostrar != _mostrarPistaScroll) {
      setState(() => _mostrarPistaScroll = mostrar);
    }
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

  /// Confirma la toma: registra como "tomó" (o "tardó" si se pasó del plazo),
  /// cancela el recordatorio tardío de esa ranura y muestra una felicitación.
  Future<void> _confirmar() async {
    if (_procesando) return;
    setState(() => _procesando = true);

    final horaProgramada = _horaProgramada;

    // Se compara contra la hora programada, no contra "ahora": si el paciente
    // estuvo en la alarma un rato, la toma sigue siendo la de las 08:00.
    //
    // El plazo es "> 15 minutos", no "> 15 minutos y pico": a los 15:00 exactos
    // la toma todavía se cuenta como "tomó". Por eso se compara la Duration
    // entera en vez de usar `inMinutes`, que trunca a 15.
    final atraso = DateTime.now().difference(horaProgramada);
    final estado = atraso > AlarmaScreen._plazoTardio
        ? EstadoToma.tardia
        : EstadoToma.tomada;

    await _fs.crearRegistroToma(
      tratamientoId: widget.tratamiento.id,
      pacienteId: widget.pacienteId,
      horaProgramada: horaProgramada,
      estado: estado,
    );

    // El recordatorio tardío de esta ranura ya no hace falta. Si era un
    // horario semanal, se reprograma para la semana siguiente; si era una
    // toma pospuesta, solo se cancela su aviso puntual.
    await _notif.cancelarRecordatorioTardioDeRanura(
      tratamientoId: widget.tratamiento.id,
      horaProgramada: horaProgramada,
      horarios: widget.tratamiento.horarios,
      nombreMedicamento: widget.tratamiento.nombreMedicamento,
    );

    await _notif.mostrarFelicitacion(
      tratamientoId: widget.tratamiento.id,
      horaProgramada: horaProgramada,
    );

    await _limpiarYSalir();
  }

  /// "Recordar": registra como pospuesta, reprograma la alarma en 5 minutos y
  /// mueve el recordatorio tardío al nuevo desfase.
  Future<void> _recordar() async {
    if (_procesando) return;
    setState(() => _procesando = true);

    final horaProgramada = _horaProgramada;

    await _fs.crearRegistroToma(
      tratamientoId: widget.tratamiento.id,
      pacienteId: widget.pacienteId,
      horaProgramada: horaProgramada,
      estado: EstadoToma.pospuesta,
    );

    // Cancela (o rearma para la próxima semana) el tardío de esta ranura.
    await _notif.cancelarRecordatorioTardioDeRanura(
      tratamientoId: widget.tratamiento.id,
      horaProgramada: horaProgramada,
      horarios: widget.tratamiento.horarios,
      nombreMedicamento: widget.tratamiento.nombreMedicamento,
    );

    // Reagenda una alarma local para dentro de 5 minutos.
    final dentro = DateTime.now().add(const Duration(minutes: 5));
    final nuevaHoraProgramada = DateTime(
      dentro.year,
      dentro.month,
      dentro.day,
      dentro.hour,
      dentro.minute,
    );
    final hora = TimeOfDay(
      hour: nuevaHoraProgramada.hour,
      minute: nuevaHoraProgramada.minute,
    );
    // Si el tratamiento termina hoy, la nueva alarma podría caer ya en el día
    // siguiente. En ese caso no se programa nada más.
    if (VigenciaTratamiento.estaVigente(
      widget.tratamiento,
      nuevaHoraProgramada,
    )) {
      await _notif.programarAlarmaDiaria(
        id: (widget.tratamiento.id.hashCode & 0x7FFFFFFF) + 1,
        hora: '${_pad(hora.hour)}:${_pad(hora.minute)}',
        nombreMedicamento: widget.tratamiento.nombreMedicamento,
        payload:
            '${widget.tratamiento.id}|${_pad(hora.hour)}:${_pad(hora.minute)}',
      );

      // El tardío de la toma pospuesta se programa 15 minutos después de la
      // nueva alarma, no de la hora original. Es una sola ejecución.
      await _notif.programarRecordatorioTardioPuntual(
        tratamientoId: widget.tratamiento.id,
        horaProgramada: nuevaHoraProgramada,
        nombreMedicamento: widget.tratamiento.nombreMedicamento,
      );
    }

    await _limpiarYSalir();
  }

  Future<void> _limpiarYSalir() async {
    _vibracionTimer?.cancel();
    _sensores.detenerVibracion();
    _sensores.restaurarBrillo();
    await _cancelarNotificacionAlarma();
    await _desactivarFlagsVentana();
    if (mounted) Navigator.of(context).pop();
  }

  /// Quita de la barra la notificación que abrió la alarma.
  ///
  /// Se cancelan también los ids reproducibles del mismo horario porque, si la
  /// alarma se abrió desde la pantalla del paciente, no hay un
  /// `idNotificacion` de respuesta. Cancelar el id de la notificación no borra
  /// la alarma semanal: eso se hace con `NotificacionesService.cancelar...`.
  Future<void> _cancelarNotificacionAlarma() async {
    final ids = <int>{};
    if (widget.idNotificacion != null && widget.idNotificacion! > 0) {
      ids.add(widget.idNotificacion!);
    }

    final horarios = widget.tratamiento.horarios;
    for (var i = 0; i < horarios.length; i++) {
      final horario = horarios[i];
      if (horario.hora != _horaTxt) continue;
      for (final dia in horario.dias) {
        ids.add(
          NotificacionesService.idDeAlarma(
            widget.tratamiento.id,
            horario.hora,
            dia,
          ),
        );
      }
      // Ids de versiones anteriores, por si la notificación ya estaba viva.
      final idAntiguo = (widget.tratamiento.id.hashCode ^ i) & 0x7FFFFFFF;
      if (idAntiguo >= 1) ids.add(idAntiguo);
    }

    // "Recordar" usa un id fijo por tratamiento.
    ids.add((widget.tratamiento.id.hashCode & 0x7FFFFFFF) + 1);

    await _ventana.cancelarNotificaciones(ids);
  }

  Future<void> _desactivarFlagsVentana() async {
    if (_flagsVentanaDesactivados) return;
    _flagsVentanaDesactivados = true;
    await _ventana.desactivarFlags();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String get _horaTxt =>
      '${_pad(widget.horaProgramada.hour)}:${_pad(widget.horaProgramada.minute)}';

  @override
  Widget build(BuildContext context) {
    final t = widget.tratamiento;
    final ahora = DateTime.now();
    final proxima = ProximaToma.calcular(
      tratamiento: t,
      ahora: ahora,
      tomaActual: _horaProgramada,
    );
    final textoRestante = VigenciaTratamiento.textoParaPaciente(t, ahora);
    final bytesFoto = _bytesFoto;
    final tieneFoto = bytesFoto != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final anchoContenido = constraints.maxWidth - 48;
            return SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  // El bloque principal ocupa al menos la pantalla. Si en un
                  // teléfono muy pequeño no cupiera, FittedBox lo reduce en
                  // bloque en vez de obligar a hacer scroll para ver YA.
                  SizedBox(
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: anchoContenido,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
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
                                                  errorBuilder: (_, _, _) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons.medication,
                                                          size: 120,
                                                          color: AppColors
                                                              .textSecondary,
                                                        ),
                                                      ),
                                                )
                                              : const Center(
                                                  child: Icon(
                                                    Icons.medication,
                                                    size: 120,
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
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
                                        '${t.nombreMedicamento}\n'
                                        'Es hora de tomar',
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
                                          onPressed: _procesando
                                              ? null
                                              : _confirmar,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.accent,
                                            foregroundColor: AppColors.onAccent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(24),
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
                                        onPressed: _procesando
                                            ? null
                                            : _recordar,
                                        child: const Text(
                                          'Recordar',
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 22,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: _mostrarPistaScroll ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'Desliza para ver más',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.white54,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _secciones(t, ahora, proxima, textoRestante),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _secciones(
    Tratamiento t,
    DateTime ahora,
    ResultadoProximaToma proxima,
    String? textoRestante,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloSeccion('Próxima toma', Icons.schedule),
          const SizedBox(height: 8),
          _cajaSeccion(
            proxima.cuando == null
                ? const Text(
                    'Esta es tu última toma',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${etiquetaDia(proxima.cuando!, ahora: ahora)} · '
                        '${horaCorta(proxima.cuando!)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ProximaToma.formatearCuentaRegresiva(
                          proxima.cuando!.difference(ahora),
                        ),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 28),
          _tituloSeccion('Historial de este medicamento', Icons.history),
          const SizedBox(height: 8),
          FutureBuilder<List<RegistroToma>>(
            future: _historialFuturo,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _cajaSeccion(
                  const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Cargando tu historial...',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (snap.hasError) {
                return _cajaSeccion(
                  const Text(
                    'No pudimos cargar tu historial ahora. '
                    'Puedes seguir con tu toma.',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                );
              }
              final registros = snap.data ?? const <RegistroToma>[];
              if (registros.isEmpty) {
                return _cajaSeccion(
                  const Text(
                    'Aún no hay tomas registradas',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                );
              }
              return Column(
                children: [
                  for (final registro in registros)
                    _filaHistorial(registro, ahora),
                ],
              );
            },
          ),
          if (textoRestante != null) ...[
            const SizedBox(height: 28),
            _tituloSeccion('Tiempo restante', Icons.timelapse),
            const SizedBox(height: 8),
            _cajaSeccion(
              Text(
                textoRestante,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tituloSeccion(String titulo, IconData icono) {
    return Row(
      children: [
        Icon(icono, color: AppColors.accent, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cajaSeccion(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }

  Widget _filaHistorial(RegistroToma registro, DateTime ahora) {
    final (etiqueta, color, icono) = switch (registro.estado) {
      EstadoToma.tomada => ('A tiempo', AppColors.accent, Icons.check_circle),
      EstadoToma.tardia => ('Tardó', AppColors.amber, Icons.timer_outlined),
      EstadoToma.olvidada => ('Olvidó', AppColors.error, Icons.cancel),
      EstadoToma.pospuesta => ('Pospuesta', AppColors.warning, Icons.schedule),
      EstadoToma.pendiente => ('Pendiente', Colors.white70, Icons.schedule),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiquetaProgramada(registro, ahora: ahora),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  etiqueta,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
