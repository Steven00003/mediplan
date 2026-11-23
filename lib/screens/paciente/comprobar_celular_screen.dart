import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../services/diagnostico_service.dart';
import '../../services/local_store.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/comprobar_celular.dart';
import '../../utils/errores_amigables.dart';
import '../../widgets/estados.dart';
import '../../widgets/lista_comprobacion_celular.dart';

typedef CargarEstadoCelular = Future<EstadoCelular> Function();
typedef AbrirAjusteCelular = Future<void> Function(PuntoCelular punto);
typedef ProbarAlarmaCelular = Future<DateTime?> Function();

/// Pantalla de ayuda para que el paciente revise su propio celular.
///
/// No toca Firestore. Lee permisos y datos del sistema, muestra una guía según
/// la marca y permite programar una alarma de prueba con la misma configuración
/// que las alarmas reales.
class ComprobarCelularScreen extends StatefulWidget {
  /// Permite inyectar el estado en las pruebas de widget sin llamar al canal
  /// nativo. En producción se deja en `null`.
  final CargarEstadoCelular? cargarEstado;

  /// Permite sustituir la apertura de Ajustes en las pruebas.
  final AbrirAjusteCelular? abrirAjuste;

  /// Permite sustituir la programación de la alarma de prueba.
  final ProbarAlarmaCelular? probarAlarma;

  const ComprobarCelularScreen({
    super.key,
    this.cargarEstado,
    this.abrirAjuste,
    this.probarAlarma,
  });

  @override
  State<ComprobarCelularScreen> createState() => _ComprobarCelularScreenState();
}

class _ComprobarCelularScreenState extends State<ComprobarCelularScreen>
    with WidgetsBindingObserver {
  final NotificacionesService _notif = NotificacionesService();
  final DiagnosticoService _diag = DiagnosticoService();

  EstadoCelular? _estado;
  AndroidNotificationChannel? _canalAlarmas;
  AndroidNotificationChannel? _canalRecordatorios;
  String? _error;
  bool _cargando = false;
  bool _abriendoAjuste = false;
  bool _probando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de los Ajustes de Android conviene refrescar el estado.
    if (state == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    if (_cargando) return;
    _cargando = true;
    if (mounted) setState(() => _error = null);
    try {
      final estado = await (widget.cargarEstado ?? _cargarEstadoReal)();
      if (!mounted) return;
      final canal = await _notif.canalDeAlarmas().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _canalAlarmas = canal;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mensajeErrorAmigable(
          e,
          contexto: 'No se pudo comprobar el celular',
        );
        _cargando = false;
      });
    }
  }

  Future<EstadoCelular> _cargarEstadoReal() async {
    final pendientes = await _notif.solicitudesPendientes();
    final notificaciones = await _notif.notificacionesHabilitadas();
    final energia = await _notif.estadoEnergia();
    final sdk =
        await _notif.androidSdkInt() ?? (energia?['sdkInt'] as num?)?.toInt();
    final fabricante = await _notif.fabricanteDispositivo();
    final pantalla = sdk != null && sdk >= 34
        ? await _notif.puedeUsarPantallaCompleta()
        : null;
    final exactas = sdk != null && sdk >= 31
        ? (energia?['canScheduleExactAlarms'] as bool?) ??
              await _notif.puedeProgramarAlarmasExactas()
        : null;
    final bateria = energia?['ignoringBatteryOptimizations'] as bool?;
    final programaciones = await _diag.obtenerProgramaciones();
    final rearme = await _diag.obtenerUltimoRearme();
    final ultimoError = await LocalStore.getUltimoErrorSincronizacion();
    final ahora = DateTime.now();

    final metaPorId = <int, ProgramacionAlarma>{
      for (final p in programaciones) p.id: p,
    };
    final alarmas = <AlarmaEnCelular>[];
    for (final pendiente in pendientes) {
      final meta = metaPorId[pendiente.id];
      final tipo = meta?.tipo ?? _tipoDesdePayload(pendiente.payload);
      final hora =
          meta?.proximaLocal(ahora) ??
          meta?.proxima ??
          horaDesdePayloadAlarma(pendiente.payload, ahora);
      alarmas.add(
        AlarmaEnCelular(
          tipo: tipo,
          hora: hora,
          esPrueba:
              pendiente.id == NotificacionesService.idAlarmaPrueba ||
              tipo == 'prueba',
        ),
      );
    }
    alarmas.sort((a, b) {
      if (a.hora == null && b.hora == null) return 0;
      if (a.hora == null) return 1;
      if (b.hora == null) return -1;
      return a.hora!.compareTo(b.hora!);
    });

    return EstadoCelular(
      sdkInt: sdk,
      fabricante: fabricante,
      versionAndroid: energia?['release'] as String?,
      notificacionesPermitidas: notificaciones,
      alarmasExactasPermitidas: exactas,
      pantallaCompletaPermitida: pantalla,
      bateriaSinRestricciones: bateria,
      alarmas: alarmas,
      ultimoRearme: rearme?.fecha,
      huerfanasCanceladasUltimoRearme:
          rearme?.huerfanasCanceladas ?? 0,
      ultimoErrorSincronizacion: ultimoError,
    );
  }

  String _tipoDesdePayload(String? payload) {
    if (payload == null || payload.isEmpty) return '';
    if (payload.startsWith(NotificacionesService.prefijoPayloadPrueba)) {
      return 'prueba';
    }
    if (payload.startsWith('recordatorio|')) return 'recordatorio_tardio';
    return '';
  }

  Future<void> _abrirAjuste(PuntoCelular punto) async {
    if (_abriendoAjuste) return;
    _abriendoAjuste = true;
    try {
      final abrir = widget.abrirAjuste;
      if (abrir != null) {
        await abrir(punto);
      } else {
        await _abrirAjusteReal(punto);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mensajeErrorAmigable(
                e,
                contexto: 'No se pudo abrir el ajuste del celular',
              ),
            ),
          ),
        );
      }
    } finally {
      _abriendoAjuste = false;
    }
    if (mounted) await _cargar();
  }

  Future<void> _abrirAjusteReal(PuntoCelular punto) async {
    switch (punto) {
      case PuntoCelular.notificaciones:
        await _notif.abrirAjustesNotificaciones();
        return;
      case PuntoCelular.alarmasExactas:
        await _notif.solicitarPermisoAlarmasExactas();
        return;
      case PuntoCelular.pantallaCompleta:
        await _notif.solicitarPermisoPantallaCompleta();
        return;
      case PuntoCelular.bateria:
        await _notif.abrirAjustesBateria();
        return;
      case PuntoCelular.detallesApp:
        await _notif.abrirDetallesApp();
        return;
    }
  }

  Future<void> _probarAlarma() async {
    if (_probando) return;
    setState(() => _probando = true);
    try {
      final cuando = await (widget.probarAlarma ?? _programarPruebaReal)();
      if (!mounted) return;
      if (cuando == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo programar la prueba. Revisa que la app siga en modo '
              'paciente.',
            ),
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alarma de prueba programada'),
          content: Text(
            'Sonará a las ${_horaConSegundos(cuando)} (en 60 segundos).\n\n'
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
      if (mounted) await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeErrorAmigable(
              e,
              contexto: 'No se pudo programar la alarma de prueba',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  Future<DateTime?> _programarPruebaReal() {
    return _notif.programarAlarmaDePrueba();
  }

  String _horaConSegundos(DateTime fecha) {
    final h = fecha.hour.toString().padLeft(2, '0');
    final m = fecha.minute.toString().padLeft(2, '0');
    final s = fecha.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Comprobar mi celular',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            color: AppColors.onGreen,
          ),
        ],
      ),
      body: estado == null
          ? (_cargando
                ? const EstadoCargando(texto: 'Revisando tu celular...')
                : EstadoError(
                    titulo: 'No pudimos revisar tu celular',
                    mensaje: _error ?? 'Vuelve a intentarlo en un momento.',
                    onReintentar: _cargar,
                  ))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.sm),
                children: [
                  _EncabezadoCelular(estado: estado),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _AvisoActualizacion(
                      mensaje: _error!,
                      onReintentar: _cargar,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _tituloSeccion('Lista de verificación'),
                  ListaComprobacionCelular(
                    puntos: [
                      for (final punto in puntosCelularParaSdk(estado.sdkInt))
                        PuntoComprobacionVista(
                          punto: punto,
                          listo: estado.listo(punto),
                        ),
                    ],
                    onAbrir: _abrirAjuste,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _tituloSeccion(
                    'Guía para ${guiaParaFabricante(estado.fabricante).nombre}',
                  ),
                  _GuiaFabricanteCard(
                    guia: guiaParaFabricante(estado.fabricante),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (mostrarFilaCanalAlarmas(estado.sdkInt))
                    _CanalAlarmasCard(
                      titulo: 'Canal de alarmas',
                      canal: _canalAlarmas,
                      notificacionesHabilitadas: estado.notificacionesPermitidas,
                      onAbrir: _abrirAjustesCanalAlarmas,
                    ),
                  if (mostrarFilaCanalAlarmas(estado.sdkInt))
                    const SizedBox(height: AppSpacing.md),
                  if (mostrarFilaCanalAlarmas(estado.sdkInt))
                    _CanalAlarmasCard(
                      titulo: 'Canal de recordatorios tardios',
                      canal: _canalRecordatorios,
                      notificacionesHabilitadas: estado.notificacionesPermitidas,
                      onAbrir: () async {
                        await _notif.abrirAjustesCanal(
                          NotificacionesService.canalRecordatoriosTardiosId,
                        );
                        if (mounted) await _cargar();
                      },
                    ),
                  if (mostrarFilaCanalAlarmas(estado.sdkInt))
                    const SizedBox(height: AppSpacing.md),
                  _tituloSeccion('Probar alarma'),
                  _ProbarAlarmaCard(
                    probando: _probando,
                    onProbar: _probarAlarma,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _tituloSeccion('Alarmas programadas en este celular'),
                  _AlarmasProgramadasCard(estado: estado),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
    );
  }

  Future<void> _abrirAjustesCanalAlarmas() async {
    await _notif.abrirAjustesCanalAlarmas();
    if (mounted) await _cargar();
  }

  Widget _tituloSeccion(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        titulo,
        style: AppType.title.copyWith(color: AppColors.onGreen),
      ),
    );
  }
}

class _CanalAlarmasCard extends StatelessWidget {
  final String titulo;
  final AndroidNotificationChannel? canal;
  final bool? notificacionesHabilitadas;
  final Future<void> Function() onAbrir;

  const _CanalAlarmasCard({
    required this.titulo,
    required this.canal,
    required this.notificacionesHabilitadas,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final enProblema = canalAlarmasEnProblema(
      canal,
      notificacionesHabilitadas: notificacionesHabilitadas,
    );
    return Card(
      color: enProblema
          ? AppColors.warning.withValues(alpha: 0.12)
          : AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enProblema
                      ? Icons.warning_amber_rounded
                      : Icons.notifications_active,
                  color: enProblema ? AppColors.warning : AppColors.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    titulo,
                    style: AppType.title.copyWith(color: AppColors.onGreen),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(fraseCanalAlarmas(
              canal,
              notificacionesHabilitadas: notificacionesHabilitadas,
            )),
            if (canal != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Importancia: ${canal!.importance.name}. '
                'Sonido: ${canal!.playSound ? 'si' : 'no'}. '
                'Vibracion: ${canal!.enableVibration ? 'si' : 'no'}.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
              onPressed: onAbrir,
              child: const Text('Abrir ajustes del canal de alarmas'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncabezadoCelular extends StatelessWidget {
  final EstadoCelular estado;

  const _EncabezadoCelular({required this.estado});

  @override
  Widget build(BuildContext context) {
    final fabricante = estado.fabricante?.trim();
    final nombreFabricante = (fabricante == null || fabricante.isEmpty)
        ? 'Fabricante no disponible'
        : fabricante;
    final restringida = estado.bateriaSinRestricciones == false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.phone_android,
                  color: AppColors.primaryStrong,
                  size: AppSizes.iconLarge,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Revisemos tu celular',
                    style: AppType.title.copyWith(color: AppColors.onGreen),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Así comprobamos que las alarmas de tus medicamentos puedan sonar '
              'a tiempo.',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              nombreFabricante,
              style: AppType.label.copyWith(color: AppColors.onGreen),
            ),
            Text(
              textoVersionAndroid(estado.sdkInt, estado.versionAndroid),
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            Text(
              textoEstadoBateria(estado.bateriaSinRestricciones),
              style: AppType.body.copyWith(
                color: restringida
                    ? AppColors.warning
                    : AppColors.textSecondary,
                fontWeight: restringida ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvisoActualizacion extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _AvisoActualizacion({
    required this.mensaje,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No se pudo actualizar el estado',
              style: AppType.body.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mensaje,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReintentar,
                child: const Text('Reintentar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuiaFabricanteCard extends StatelessWidget {
  final GuiaFabricante guia;

  const _GuiaFabricanteCard({required this.guia});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < guia.pasos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: AppColors.onGreen,
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        guia.pasos[i],
                        style: AppType.body.copyWith(color: AppColors.onGreen),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              notaGuiaFabricante,
              style: AppType.label.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbarAlarmaCard extends StatelessWidget {
  final bool probando;
  final VoidCallback onProbar;

  const _ProbarAlarmaCard({required this.probando, required this.onProbar});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comprueba que la alarma abra la app y suene como las de verdad.',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: probando ? null : onProbar,
                icon: const Icon(Icons.alarm),
                label: Text(
                  probando ? 'Programando...' : 'Probar alarma en 60 s',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlarmasProgramadasCard extends StatelessWidget {
  final EstadoCelular estado;

  const _AlarmasProgramadasCard({required this.estado});

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (estado.alarmas.isEmpty)
              Text(
                'No hay alarmas ni avisos programados en este celular.',
                style: AppType.body.copyWith(color: AppColors.textSecondary),
              )
            else ...[
              Text(
                '${estado.alarmas.length} programadas',
                style: AppType.body.copyWith(
                  color: AppColors.onGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final alarma in estado.alarmas)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _FilaAlarma(alarma: alarma, ahora: ahora),
                ),
            ],
            const Divider(height: AppSpacing.md),
            _FilaDato(
              etiqueta: 'Último rearmado',
              valor: textoFechaHoraLocal(estado.ultimoRearme),
            ),
            if (estado.huerfanasCanceladasUltimoRearme > 0)
              _FilaDato(
                etiqueta: 'Huérfanas canceladas',
                valor: '${estado.huerfanasCanceladasUltimoRearme}',
              ),
            if (estado.ultimoErrorSincronizacion != null &&
                estado.ultimoErrorSincronizacion!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Card(
                color: AppColors.background,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.sync_problem,
                        color: AppColors.warning,
                        size: AppSizes.icon,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Último error de sincronización',
                              style: AppType.label.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              estado.ultimoErrorSincronizacion!,
                              style: AppType.body.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaAlarma extends StatelessWidget {
  final AlarmaEnCelular alarma;
  final DateTime ahora;

  const _FilaAlarma({required this.alarma, required this.ahora});

  @override
  Widget build(BuildContext context) {
    final tipo = alarma.esPrueba
        ? 'Alarma de prueba'
        : etiquetaTipoAlarma(alarma.tipo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          alarma.esPrueba ? Icons.alarm : Icons.notifications_active_outlined,
          color: AppColors.primaryStrong,
          size: AppSizes.iconSmall,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            tipo,
            style: AppType.body.copyWith(color: AppColors.onGreen),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            textoHoraLocal(alarma.hora, ahora),
            textAlign: TextAlign.right,
            style: AppType.label.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _FilaDato extends StatelessWidget {
  final String etiqueta;
  final String valor;

  const _FilaDato({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            etiqueta,
            style: AppType.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: AppType.body.copyWith(
              color: AppColors.onGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
