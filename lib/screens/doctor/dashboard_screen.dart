import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/paciente.dart';
import '../../models/registro_toma.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/push_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_page_route.dart';
import '../../theme/app_tokens.dart';
import '../../utils/errores_amigables.dart';
import '../../widgets/banner_sin_conexion.dart';
import '../../widgets/confirmar_salida_app.dart';
import '../../widgets/estados.dart';
import '../../widgets/lista_pacientes.dart';
import '../../widgets/menu_ayuda.dart';
import '../../widgets/snackbars.dart';
import 'detalle_paciente_screen.dart';
import 'mi_perfil_medico_screen.dart';
import 'nuevo_paciente_screen.dart';

/// Dashboard del cuidador: lista de pacientes vinculados en tiempo real y
/// actividad reciente de tomas.
///
/// Escucha en tiempo real la colección `registrosToma` de sus pacientes y:
///  - refleja automáticamente los cambios de estado (tomada/pospuesta/olvidada),
///  - muestra solo un resumen local de tomas olvidadas, agrupado por emisión,
///    mientras la app está visible. Las confirmaciones no generan aviso local
///    ni push. FCM solo se usa para la alerta de 5 días sin tomas (ver
///    `PushService`).
///
/// Además registra el token FCM de este dispositivo en sus pacientes, que es lo
/// que permite al dispositivo del paciente enviarle esa alerta.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _auth = AuthService();
  final FirestoreService _fs = FirestoreService();
  final NotificacionesService _notif = NotificacionesService();
  final PushService _push = PushService();

  // Seguimiento para notificaciones locales (deduplicación por registro).
  final Set<String> _notificados = {};
  final Map<String, String> _nombresPaciente = {};
  final Map<String, String> _nombresMedicamento = {};
  StreamSubscription<List<RegistroToma>>? _registrosSub;
  List<String> _pacienteIds = [];
  int _reintentoPacientes = 0;

  @override
  void initState() {
    super.initState();
    // Cubre también una sesión de cuidador ya iniciada antes de esta versión.
    unawaited(_notif.migrarAlarmasDeCuidador());
    unawaited(_push.registrarCuidador());
    _iniciarSuscripcion();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _pedirNotificacionesSiFaltan(),
    );
  }

  Future<void> _pedirNotificacionesSiFaltan() async {
    if (!mounted) return;
    final notif = NotificacionesService();
    final habilitadas = await notif.notificacionesHabilitadas();
    if (habilitadas != false || !mounted) return;
    final pedir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notificaciones de alertas'),
        content: const Text(
          'MediPlan te avisa si un paciente lleva 5 dias sin tomas registradas. '
          'Activa las notificaciones para no perder esos avisos. Si las alertas '
          'llegan en silencio, revisa el canal Alertas de tus pacientes en los '
          'ajustes de la app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
    if (pedir == true && mounted) {
      await notif.pedirPermiso();
    }
  }

  @override
  void dispose() {
    _registrosSub?.cancel();
    super.dispose();
  }

  /// Suscribe al estado de la app para notificar al cuidador.
  void _iniciarSuscripcion() {
    _fs.streamPacientesDelCuidador().listen((pacientes) {
      final ids = pacientes.map((p) => p.id).toList();
      _nombresPaciente
        ..clear()
        ..addEntries(pacientes.map((p) => MapEntry(p.id, p.nombre)));
      if (_mismasListas(ids, _pacienteIds)) return;

      _registrosSub?.cancel();
      _pacienteIds = ids;
      // Los pacientes recién creados nacen sin token: reintentar publicarlo.
      unawaited(_push.sincronizarTokenConPacientes());
      _registrosSub = _fs
          .streamRegistrosDePacientes(ids)
          .listen(_procesarRegistros, onError: (_) {});
    });
  }

  bool _mismasListas(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.toSet().containsAll(b);
  }

  Future<void> _procesarRegistros(List<RegistroToma> registros) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Solo las tomas olvidadas generan aviso local. Las confirmaciones
    // (tomada/tardía/pospuesta) no notifican al cuidador: se ven en la lista de
    // actividad reciente y en el historial. Las olvidadas se agrupan en una
    // sola notificación por emisión, porque la reconciliación puede marcar
    // varias a la vez (un backfill de días) y una por cada dosis sería ruido.
    var olvidadas = 0;
    String? detalleOlvidada;
    for (final r in registros) {
      if (r.estado != EstadoToma.olvidada) continue;
      if (_notificados.contains(r.id)) continue;
      _notificados.add(r.id);

      final nombrePaciente = _nombresPaciente[r.pacienteId] ?? 'Paciente';
      String nombreMed = _nombresMedicamento[r.tratamientoId] ?? 'medicamento';
      if (!_nombresMedicamento.containsKey(r.tratamientoId)) {
        final t = await _fs.getTratamiento(r.tratamientoId);
        if (t?.nombreMedicamento != null) {
          nombreMed = t!.nombreMedicamento;
          _nombresMedicamento[r.tratamientoId] = nombreMed;
        }
      }

      // La lista llega de la más reciente a la más antigua: la primera
      // olvidada es la más reciente y es la que se muestra en el resumen.
      detalleOlvidada ??=
          '$nombrePaciente no tomó $nombreMed (${_horaTxt(r.horaProgramada)}).';
      olvidadas++;
    }

    if (olvidadas > 0 && _appVisible()) {
      await _notif.mostrarNotificacion(
        id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
        titulo: olvidadas == 1 ? 'Toma olvidada' : '$olvidadas tomas olvidadas',
        cuerpo: olvidadas == 1
            ? detalleOlvidada!
            : '$detalleOlvidada Y ${olvidadas - 1} más.',
      );
    }
  }

  /// El resumen de tomas olvidadas solo se muestra con la app visible. El
  /// aviso de 5 días sin tomas llega por FCM y se respalda en el detalle del
  /// paciente, así que no se duplica aquí.
  bool _appVisible() {
    final estado = WidgetsBinding.instance.lifecycleState;
    return estado != AppLifecycleState.paused &&
        estado != AppLifecycleState.hidden &&
        estado != AppLifecycleState.detached;
  }

  static String _horaTxt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return ConfirmarSalidaApp(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis pacientes'),
          actions: [
            IconButton(
              tooltip: 'Mi perfil',
              onPressed: () {
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const MiPerfilMedicoScreen()),
                );
              },
              icon: const Icon(Icons.person_outline),
            ),
            const AyudaBoton(),
            Semantics(
              button: true,
              label: 'Cerrar sesión',
              excludeSemantics: true,
              child: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Cerrar sesión',
                onPressed: () async {
                  // Antes de cerrar sesión: dejar de recibir push en este teléfono.
                  await _push.cerrarSesionCuidador();
                  await _auth.cerrarSesion();
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(
              context,
            ).push(AppPageRoute(builder: (_) => const NuevoPacienteScreen()));
          },
          icon: const Icon(Icons.person_add),
          label: const Text('Nuevo paciente'),
        ),
        body: _uidVacio
            ? const Center(child: Text('No hay sesión activa'))
            : Column(
                children: [
                  const BannerSinConexion(
                    mensaje: 'Sin conexión. Puede que estés viendo datos desactualizados.',
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      key: ValueKey('pacientes-$_reintentoPacientes'),
                      stream: FirebaseFirestore.instance
                          .collection('pacientes')
                          .where('cuidadorId', isEqualTo: uid)
                          .snapshots(includeMetadataChanges: true),
                      builder: (context, snap) {
                        reportarConexionDesde(
                          context,
                          snap.data?.metadata.isFromCache ?? true,
                        );
                        if (snap.hasError) {
                          return EstadoError(
                            mensaje: mensajeErrorAmigable(
                              snap.error!,
                              contexto: 'Error cargando pacientes del cuidador',
                            ),
                            onReintentar: () =>
                                setState(() => _reintentoPacientes++),
                          );
                        }
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const EstadoCargando(
                            texto: 'Cargando pacientes...',
                          );
                        }
                        final pacientes = snap.data!.docs
                            .map(
                              (d) => Paciente.fromMap(
                                d.id,
                                d.data() as Map<String, dynamic>,
                              ),
                            )
                            .toList();
                        if (pacientes.isEmpty) {
                          return EstadoVacio(
                            icono: Icons.group_off,
                            titulo: 'Aún no tienes pacientes',
                            mensaje: 'Agrega un paciente y compártele el código de vinculación.',
                            accion: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  AppPageRoute(
                                    builder: (_) => const NuevoPacienteScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text('Agregar paciente'),
                            ),
                          );
                        }
                        return ListaPacientes(
                          pacientes: pacientes,
                          onTap: (p) async {
                            final eliminado = await Navigator.of(context)
                                .push<bool>(
                                  AppPageRoute(
                                    builder: (_) =>
                                        DetallePacienteScreen(pacienteId: p.id),
                                  ),
                                );
                            if (eliminado == true && context.mounted) {
                              mostrarSnackExito(context, 'Paciente eliminado.');
                            }
                          },
                          footer: _ActividadReciente(
                            pacienteIds: _pacienteIds,
                            nombresPaciente: _nombresPaciente,
                            nombresMedicamento: _nombresMedicamento,
                            fs: _fs,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  bool get _uidVacio => FirebaseAuth.instance.currentUser == null;
}

/// Panel de actividad reciente: refleja en tiempo real las confirmaciones de
/// los pacientes del cuidador (mecanismo principal de alerta, sin servidor).
class _ActividadReciente extends StatefulWidget {
  final List<String> pacienteIds;
  final Map<String, String> nombresPaciente;
  final Map<String, String> nombresMedicamento;
  final FirestoreService fs;

  const _ActividadReciente({
    required this.pacienteIds,
    required this.nombresPaciente,
    required this.nombresMedicamento,
    required this.fs,
  });

  @override
  State<_ActividadReciente> createState() => _ActividadRecienteState();
}

class _ActividadRecienteState extends State<_ActividadReciente> {
  int _reintento = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RegistroToma>>(
      key: ValueKey('actividad-$_reintento'),
      stream: widget.fs.streamRegistrosDePacientes(
        widget.pacienteIds,
        limite: 10,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return EstadoError(
            mensaje: mensajeErrorAmigable(
              snap.error!,
              contexto: 'Error cargando actividad reciente',
            ),
            onReintentar: () => setState(() => _reintento++),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const EstadoCargando(texto: 'Cargando actividad...');
        }
        final registros = snap.data ?? const [];
        final confirmados = registros
            .where(
              (r) =>
                  r.estado == EstadoToma.tomada ||
                  r.estado == EstadoToma.tardia ||
                  r.estado == EstadoToma.pospuesta,
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actividad reciente',
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (confirmados.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'Aún no hay confirmaciones. Se verán acá en tiempo real.',
                    style: AppType.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ...confirmados.map((r) {
                final nombrePaciente =
                    widget.nombresPaciente[r.pacienteId] ?? 'Paciente';
                final nombreMed =
                    widget.nombresMedicamento[r.tratamientoId] ?? 'medicamento';
                final tomada = r.estado == EstadoToma.tomada;
                final tardia = r.estado == EstadoToma.tardia;
                final (icono, color) = tardia
                    ? (Icons.timer_outlined, AppColors.amber)
                    : tomada
                    ? (Icons.check_circle, AppColors.accent)
                    : (Icons.snooze, AppColors.warning);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: ListTile(
                    leading: Icon(icono, color: color),
                    title: Text(
                      tardia
                          ? '$nombrePaciente tomó $nombreMed tarde'
                          : tomada
                          ? '$nombrePaciente tomó $nombreMed'
                          : '$nombrePaciente pospuso $nombreMed',
                      style: AppType.body.copyWith(color: AppColors.onGreen),
                    ),
                    // `horaConfirmacion` es null en las olvidadas, pero esas no
                    // llegan aquí; el fallback cubre registros antigos.
                    subtitle: Text(
                      _hora(r.horaConfirmacion ?? r.horaProgramada),
                      style: AppType.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  String _hora(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
