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
import '../../widgets/confirmar_salida_app.dart';
import 'detalle_paciente_screen.dart';
import 'nuevo_paciente_screen.dart';

/// Dashboard del cuidador: lista de pacientes vinculados en tiempo real y
/// actividad reciente de tomas.
///
/// Escucha en tiempo real la colección `registrosToma` de sus pacientes y:
///  - refleja automáticamente los cambios de estado (tomada/pospuesta/olvidada),
///  - muestra una notificación local al cuidador con la app visible: una por
///    cada confirmación, y las olvidadas agrupadas en un solo resumen por
///    emisión. Con la app en segundo plano/cerrada el aviso lo pone FCM (ver
///    `PushService`); avisar aquí también daría duplicados. Sin credencial de
///    push este listener es la única vía y se muestra igual.
///
/// Además registra el token FCM de este dispositivo en sus pacientes, que es lo
/// que permite al dispositivo del paciente enviarle el push (ver `PushService`).
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

  @override
  void initState() {
    super.initState();
    unawaited(_push.registrarCuidador());
    _iniciarSuscripcion();
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

    // Las confirmaciones avisan de una en una; las olvidadas se agrupan en una
    // sola notificación por emisión, porque la reconciliación puede marcar
    // varias a la vez (un backfill de días) y una por cada dosis sería ruido.
    var olvidadas = 0;
    String? detalleOlvidada;
    for (final r in registros) {
      if (!_ameritaAviso(r.estado)) continue;
      if (_notificados.contains(r.id)) continue;
      _notificados.add(r.id);

      final nombrePaciente =
          _nombresPaciente[r.pacienteId] ?? 'Paciente';
      String nombreMed = _nombresMedicamento[r.tratamientoId] ?? 'medicamento';
      if (!_nombresMedicamento.containsKey(r.tratamientoId)) {
        final t = await _fs.getTratamiento(r.tratamientoId);
        if (t?.nombreMedicamento != null) {
          nombreMed = t!.nombreMedicamento;
          _nombresMedicamento[r.tratamientoId] = nombreMed;
        }
      }

      if (r.estado == EstadoToma.olvidada) {
        // La lista llega de la más reciente a la más antigua: la primera
        // olvidada es la más reciente y es la que se muestra en el resumen.
        detalleOlvidada ??=
            '$nombrePaciente no tomó $nombreMed (${_horaTxt(r.horaProgramada)}).';
        olvidadas++;
        continue;
      }

      final estadoTxt = _verbo(r.estado);
      if (!_push.pushHabilitado || _appVisible()) {
        await _notif.mostrarNotificacion(
          id: r.id.hashCode & 0x7FFFFFFF,
          titulo: _tituloNotificacion(r.estado),
          cuerpo: '$nombrePaciente $estadoTxt $nombreMed.',
        );
      }
    }

    if (olvidadas > 0 && (!_push.pushHabilitado || _appVisible())) {
      await _notif.mostrarNotificacion(
        id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
        titulo: olvidadas == 1 ? 'Toma olvidada' : '$olvidadas tomas olvidadas',
        cuerpo: olvidadas == 1
            ? detalleOlvidada!
            : '$detalleOlvidada Y ${olvidadas - 1} más.',
      );
    }
  }

  /// La app está visible cuando FCM no enseña la notificación (la deja al
  /// código). Si no lo está, la muestra el sistema y avisar aquí daría
  /// duplicados.
  bool _appVisible() {
    final estado = WidgetsBinding.instance.lifecycleState;
    return estado != AppLifecycleState.paused &&
        estado != AppLifecycleState.hidden &&
        estado != AppLifecycleState.detached;
  }

/// Si un estado amerita aviso al cuidador.
  ///
  /// Incluye `tardia` porque la toma **se tomó**: lo que hay que señalar es que
  /// llegó con retraso, y el cuidador es quien puede validar si eso importa.
  /// Incluye también `olvidada`: la escribe sola la reconciliación de
  /// `OmitidasService` y es el aviso más importante (el paciente NO tomó). Las
  /// olvidadas se agrupan en una sola notificación por emisión para que un
  /// backfill de varios días no convierta el dashboard en ruido.
  bool _ameritaAviso(EstadoToma e) =>
      e == EstadoToma.tomada ||
      e == EstadoToma.tardia ||
      e == EstadoToma.pospuesta ||
      e == EstadoToma.olvidada;

  static String _horaTxt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _tituloNotificacion(EstadoToma e) {
    switch (e) {
      case EstadoToma.tomada:
        return 'Toma confirmada';
      case EstadoToma.tardia:
        return 'Toma tardía';
      case EstadoToma.pospuesta:
        return 'Toma pospuesta';
      default:
        return 'Toma actualizada';
    }
  }

  /// Cómo se describe la acción del paciente, ya gasto el verbo "tomó" para
  /// que el texto no suene a que tomó tarde y a la vez no se confirmara.
  static String _verbo(EstadoToma e) {
    switch (e) {
      case EstadoToma.tomada:
        return 'confirmó';
      case EstadoToma.tardia:
        return 'confirmó tarde';
      case EstadoToma.pospuesta:
        return 'pospuesta (recuerda)';
      default:
        return 'actualizó';
    }
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
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
              onPressed: () async {
                // Antes de cerrar sesión: dejar de recibir push en este teléfono.
                await _push.cerrarSesionCuidador();
                await _auth.cerrarSesion();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NuevoPacienteScreen(),
              ),
            );
          },
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          icon: const Icon(Icons.person_add),
          label: const Text('Nuevo paciente'),
        ),
        body: _uidVacio
            ? const Center(child: Text('No hay sesión activa'))
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('pacientes')
                    .where('cuidadorId', isEqualTo: uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(
                      child: Text('Error al cargar pacientes'),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final pacientes = snap.data!.docs
                      .map((d) =>
                          Paciente.fromMap(d.id, d.data() as Map<String, dynamic>))
                      .toList();
                  if (pacientes.isEmpty) {
                    return _EmptyState(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NuevoPacienteScreen(),
                          ),
                        );
                      },
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      ...pacientes.map(
                        (p) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.onAccent,
                              child: const Icon(Icons.person),
                            ),
                            title: Text(p.nombre,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            subtitle: Text('Código: ${p.codigoVinculacion}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DetallePacienteScreen(
                                    pacienteId: p.id,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ActividadReciente(
                        pacienteIds: _pacienteIds,
                        nombresPaciente: _nombresPaciente,
                        nombresMedicamento: _nombresMedicamento,
                        fs: _fs,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  bool get _uidVacio =>
      FirebaseAuth.instance.currentUser == null;
}

/// Panel de actividad reciente: refleja en tiempo real las confirmaciones de
/// los pacientes del cuidador (mecanismo principal de alerta, sin servidor).
class _ActividadReciente extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return StreamBuilder<List<RegistroToma>>(
      stream: fs.streamRegistrosDePacientes(pacienteIds, limite: 10),
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox.shrink();
        }
        final registros = snap.data ?? const [];
final confirmados = registros
            .where((r) =>
                r.estado == EstadoToma.tomada ||
                r.estado == EstadoToma.tardia ||
                r.estado == EstadoToma.pospuesta)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actividad reciente',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (confirmados.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Aún no hay confirmaciones. Se verán acá en tiempo real.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...confirmados.map((r) {
                final nombrePaciente =
                    nombresPaciente[r.pacienteId] ?? 'Paciente';
                final nombreMed = nombresMedicamento[r.tratamientoId] ??
                    'medicamento';
final tomada = r.estado == EstadoToma.tomada;
                final tardia = r.estado == EstadoToma.tardia;
                final (icono, color) = tardia
                    ? (Icons.timer_outlined, AppColors.amber)
                    : tomada
                        ? (Icons.check_circle, AppColors.accent)
                        : (Icons.snooze, AppColors.warning);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(icono, color: color),
                    title: Text(tardia
                        ? '$nombrePaciente tomó $nombreMed tarde'
                        : tomada
                            ? '$nombrePaciente tomó $nombreMed'
                            : '$nombrePaciente pospuso $nombreMed'),
                    // `horaConfirmacion` es null en las olvidadas, pero esas no
                    // llegan aquí; el fallback cubre registros antigos.
                    subtitle:
                        Text(_hora(r.horaConfirmacion ?? r.horaProgramada)),
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_off, size: 80, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Todavía no tienes pacientes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Agrega un paciente y compártele el código de vinculación.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.person_add),
              label: const Text('Agregar paciente'),
            ),
          ],
        ),
      ),
    );
  }
}
