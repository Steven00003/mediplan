import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../services/diagnostico_service.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';

/// Diagnóstico local de alarmas. Solo se abre desde `kDebugMode`.
///
/// No toca Firestore: muestra el estado real del dispositivo y permite lanzar
/// una alarma de prueba para verificar el escenario de pantalla bloqueada.
class DiagnosticoAlarmaScreen extends StatefulWidget {
  const DiagnosticoAlarmaScreen({super.key});

  @override
  State<DiagnosticoAlarmaScreen> createState() =>
      _DiagnosticoAlarmaScreenState();
}

class _DiagnosticoAlarmaScreenState extends State<DiagnosticoAlarmaScreen> {
  final NotificacionesService _notif = NotificacionesService();
  final DiagnosticoService _diag = DiagnosticoService();

  bool _cargando = true;
  bool? _notificacionesHabilitadas;
  bool? _pantallaCompleta;
  AndroidNotificationChannel? _canal;
  Map<String, dynamic>? _energia;
  List<PendingNotificationRequest> _pendientes = const [];
  List<ProgramacionAlarma> _programaciones = const [];
  List<IntentoAperturaAlarma> _intentos = const [];
  RearmeAlarmas? _ultimoRearme;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notificaciones = await _notif.notificacionesHabilitadas();
    final pantalla = await _notif.puedeUsarPantallaCompleta();
    final canal = await _notif.canalDeAlarmas();
    final energia = await _notif.estadoEnergia();
    final pendientes = await _notif.solicitudesPendientes();
    final programaciones = await _diag.obtenerProgramaciones();
    final intentos = await _diag.obtenerIntentos();
    final ultimoRearme = await _diag.obtenerUltimoRearme();
    if (!mounted) return;
    setState(() {
      _notificacionesHabilitadas = notificaciones;
      _pantallaCompleta = pantalla;
      _canal = canal;
      _energia = energia;
      _pendientes = pendientes;
      _programaciones = programaciones;
      _intentos = intentos;
      _ultimoRearme = ultimoRearme;
      _cargando = false;
    });
  }

  Future<void> _probarAlarma() async {
    try {
      await _notif.programarAlarmaDePrueba();
      if (!mounted) return;
      final cuando = DateTime.now().add(const Duration(seconds: 60));
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alarma de prueba programada'),
          content: Text(
            'Sonará a las ${_hora(cuando)} (en 60 segundos).\n\n'
            'Para probar el caso real, bloquea el teléfono o cierra la app. '
            'Al tocarla se abrirá una pantalla de prueba y no se registrará '
            'ninguna toma.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo programar la prueba: $e')),
      );
    }
  }

  Future<void> _abrirAjustesNotificaciones() async {
    await _notif.abrirAjustesNotificaciones();
  }

  Future<void> _abrirAjustesBateria() async {
    await _notif.abrirAjustesBateria();
  }

  Future<void> _abrirAjustesAlarmasExactas() async {
    await _notif.abrirAjustesAlarmasExactas();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(
          child: Text('El diagnóstico solo está disponible en depuración.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diagnóstico de alarma'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _seccion('Estado del dispositivo'),
                _fila('Notificaciones', _textoBool(_notificacionesHabilitadas)),
                _fila(
                  'Canal de alarmas',
                  _canal == null
                      ? 'No encontrado'
                      : '${_canal!.importance.name} '
                            '(${_canal!.importance.value})',
                ),
                _fila(
                  'No molestar',
                  _textoDnd(_energia?['interruptionFilter']),
                ),
                _fila(
                  'Ahorro de batería',
                  _textoBool(_energia?['powerSaveMode'] as bool?),
                ),
                _fila('Doze', _textoBool(_energia?['deviceIdleMode'] as bool?)),
                _fila(
                  'Exento de optimización',
                  _textoBool(
                    _energia?['ignoringBatteryOptimizations'] as bool?,
                  ),
                ),
                _fila(
                  'Alarmas exactas',
                  _textoBool(_energia?['canScheduleExactAlarms'] as bool?),
                ),
                _fila('Pantalla completa', _textoBool(_pantallaCompleta)),
                _fila(
                  'Android',
                  '${_energia?['release'] ?? '?'} '
                      '(API ${_energia?['sdkInt'] ?? '?'})',
                ),
                const SizedBox(height: 20),
                _seccion('Rearme de la ventana'),
                _fila(
                  'Último rearme',
                  _ultimoRearme == null
                      ? 'Todavía no'
                      : _fecha(_ultimoRearme!.fecha),
                ),
                _fila(
                  'Alarmas puntuales',
                  _ultimoRearme == null
                      ? 'Sin datos'
                      : '${_ultimoRearme!.cantidad} en '
                            '${_ultimoRearme!.tratamientos} tratamientos',
                ),
                const SizedBox(height: 20),
                _seccion('Alarmas programadas (${_pendientes.length})'),
                if (_pendientes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No hay notificaciones pendientes.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ..._pendientes.map(_tarjetaPendiente),
                const SizedBox(height: 20),
                _seccion('Últimos intentos de apertura (${_intentos.length})'),
                if (_intentos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Todavía no hay intentos registrados.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ..._intentos.map(_tarjetaIntento),
                const SizedBox(height: 20),
                _seccion('Acciones'),
                ElevatedButton.icon(
                  onPressed: _probarAlarma,
                  icon: const Icon(Icons.alarm),
                  label: const Text('Probar alarma en 60 s'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _abrirAjustesNotificaciones,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Ajustes de notificaciones'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _abrirAjustesBateria,
                  icon: const Icon(Icons.battery_saver_outlined),
                  label: const Text('Ajustes de batería'),
                ),
                if (_energia?['canScheduleExactAlarms'] == false) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _abrirAjustesAlarmasExactas,
                    icon: const Icon(Icons.alarm_add_outlined),
                    label: const Text('Permitir alarmas exactas'),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _seccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        titulo,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.onGreen,
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valor,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaPendiente(PendingNotificationRequest pendiente) {
    final meta = _buscarProgramacion(pendiente.id);
    final proxima = meta?.proximaLocal(DateTime.now());
    final modo = meta?.modo ?? _modoInferido(pendiente);
    final tipo = _tipoLegible(meta?.tipo ?? 'sin metadatos');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pendiente.title ?? '(sin título)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.onGreen,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Próxima: ${proxima == null ? 'desconocida' : _fecha(proxima)}',
              style: const TextStyle(color: AppColors.onGreen),
            ),
            Text(
              'Modo: $modo',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            Text(
              'Tipo: $tipo · id ${pendiente.id}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if ((pendiente.payload ?? '').isNotEmpty)
              Text(
                'Payload: ${pendiente.payload}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaIntento(IntentoAperturaAlarma intento) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_fecha(intento.fecha)} · ${intento.resultado}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.onGreen,
              ),
            ),
            Text(
              intento.motivo,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            Text(
              'Payload: ${intento.payload}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ProgramacionAlarma? _buscarProgramacion(int id) {
    for (final p in _programaciones) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _tipoLegible(String tipo) {
    switch (tipo) {
      case 'principal_puntual':
        return 'principal (ventana)';
      case 'principal':
        return 'principal (semanal antigua)';
      default:
        return tipo;
    }
  }

  String _modoInferido(PendingNotificationRequest pendiente) {
    final titulo = pendiente.title ?? '';
    if (titulo == 'Hora de tu medicina' || titulo == 'Prueba de alarma') {
      return 'alarmClock (inferido)';
    }
    if (titulo == 'Tu medicina se acerca' || titulo.contains('Ya tomaste')) {
      return 'exactAllowWhileIdle (inferido)';
    }
    return 'desconocido';
  }

  String _textoBool(bool? valor) {
    if (valor == null) return 'Desconocido';
    return valor ? 'Sí' : 'No';
  }

  String _textoDnd(Object? filtro) {
    switch (filtro) {
      case 1:
        return 'Desactivado';
      case 2:
        return 'Solo prioridad';
      case 3:
        return 'Total';
      case 4:
        return 'Solo alarmas';
      default:
        return 'Desconocido';
    }
  }

  String _fecha(DateTime fecha) {
    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    return '$d/$m ${_hora(fecha)}';
  }

  String _hora(DateTime fecha) {
    final h = fecha.hour.toString().padLeft(2, '0');
    final m = fecha.minute.toString().padLeft(2, '0');
    final s = fecha.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
