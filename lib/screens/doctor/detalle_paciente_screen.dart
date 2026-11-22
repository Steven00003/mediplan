import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/estado_dispositivo.dart';
import '../../models/paciente.dart';
import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../services/alerta_sin_tomas_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/sincronizacion_paciente_service.dart';
import '../../services/vinculacion_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_page_route.dart';
import '../../theme/app_tokens.dart';
import '../../utils/abrir_marcador.dart';
import '../../utils/errores_amigables.dart';
import '../../utils/estado_codigo_vinculacion.dart';
import '../../utils/etiqueta_toma.dart';
import '../../utils/estadisticas.dart';
import '../../utils/registros_toma.dart';
import '../../utils/reporte_estado_dispositivo.dart';
import '../../utils/resumen_vinculacion.dart';
import '../../utils/telefono_emergencia.dart';
import '../../widgets/avatar_paciente.dart';
import '../../widgets/banner_sin_conexion.dart';

import '../../widgets/dialogo_accion_delicada.dart';
import '../../widgets/dialogo_eliminar_paciente.dart';
import '../../widgets/estados.dart';
import '../../widgets/snackbars.dart';
import '../../widgets/tarjeta_medicamento.dart';
import '../../widgets/tarjeta_paciente.dart';
import 'editar_paciente_screen.dart';
import 'editar_tratamiento_screen.dart';

/// Detalle de un paciente: código de vinculación, sus tratamientos y un
/// resumen del estado de cumplimiento.
class DetallePacienteScreen extends StatefulWidget {
  final String pacienteId;
  const DetallePacienteScreen({super.key, required this.pacienteId});

  factory DetallePacienteScreen.porId(String pacienteId) =>
      DetallePacienteScreen(pacienteId: pacienteId);

  @override
  State<DetallePacienteScreen> createState() => _DetallePacienteScreenState();
}

class _DetallePacienteScreenState extends State<DetallePacienteScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pacientes')
          .doc(widget.pacienteId)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        reportarConexionDesde(context, snap.data?.metadata.isFromCache ?? true);
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: EstadoCargando(texto: 'Cargando paciente...'),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: EstadoError(
              mensaje: mensajeErrorAmigable(
                snap.error!,
                contexto: 'Error cargando detalle del paciente',
              ),
            ),
          );
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('Paciente no encontrado')),
          );
        }
        final paciente = Paciente.fromMap(snap.data!.id, snap.data!.data()!);
        return _DetalleBody(paciente: paciente);
      },
    );
  }
}

/// Detalle de un paciente, con navegación por pestañas.
///
/// La cabecera (ficha, código de vinculación y desvinculación) queda **fuera**
/// de las pestañas, siempre visible: el código es lo que el cuidador necesita
/// en cualquier momento y así no desaparece al cambiar de pestaña. Lo único que
/// entra en las pestañas es el contenido del tratamiento.
class _DetalleBody extends StatefulWidget {
  final Paciente paciente;
  const _DetalleBody({required this.paciente});

  @override
  State<_DetalleBody> createState() => _DetalleBodyState();
}

class _DetalleBodyState extends State<_DetalleBody> {
  /// Arranca en "Horario" (índice 1): es la pestaña de trabajo del cuidador.
  int _pestana = 1;

  bool _eliminando = false;

  Future<void> _confirmarEliminarPaciente() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) =>
          DialogoEliminarPaciente(nombrePaciente: widget.paciente.nombre),
    );
    if (confirmado != true || !mounted) return;
    await _ejecutarEliminacion();
  }

  Future<void> _ejecutarEliminacion() async {
    if (_eliminando) return;
    setState(() => _eliminando = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Eliminando a ${widget.paciente.nombre}...',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await FirestoreService().eliminarPaciente(widget.paciente.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      HapticFeedback.mediumImpact();
      mostrarSnackExito(context, 'Paciente eliminado.');
      // El detalle se abrió desde la lista: al volver a la raíz se ve el
      // dashboard actualizado por su propio stream.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _eliminando = false);

      final reintentar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: AppColors.error),
          title: const Text('No se pudo eliminar'),
          content: Text(
            '${mensajeErrorAmigable(e, contexto: 'Error eliminando paciente')} '
            'Puedes reintentar; los datos que ya se borraron no se duplican.',
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
      if (reintentar == true && mounted) {
        await _ejecutarEliminacion();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paciente = widget.paciente;
    final vinculado =
        paciente.dispositivoVinculadoId != null &&
        paciente.dispositivoVinculadoId!.isNotEmpty;

    return PopScope(
      canPop: !_eliminando,
      child: Scaffold(
        appBar: AppBar(
          title: Text(paciente.nombre),
          actions: [
            IconButton(
              tooltip: 'Editar',
              onPressed: _eliminando
                  ? null
                  : () {
                      Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) =>
                              EditarPacienteScreen(paciente: paciente),
                        ),
                      );
                    },
              icon: const Icon(Icons.edit),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              enabled: !_eliminando,
              onSelected: (valor) {
                if (valor == 'eliminar') {
                  _confirmarEliminarPaciente();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'eliminar',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, color: AppColors.error),
                      SizedBox(width: 8),
                      Text(
                        'Eliminar paciente',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _eliminando
              ? null
              : () {
                  Navigator.of(context).push(
                    AppPageRoute(
                      builder: (_) => EditarTratamientoScreen(
                        pacienteId: paciente.id,
                        esNuevo: true,
                      ),
                    ),
                  );
                },
          icon: const Icon(Icons.add),
          label: const Text('Nuevo medicamento'),
        ),
        body: Column(
          children: [
            const BannerSinConexion(
              mensaje:
                  'Sin conexión. Puede que estés viendo datos desactualizados.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                children: [
                  _FichaPaciente(paciente: paciente),
                  const SizedBox(height: AppSpacing.xs),
                  SeccionVinculacionDispositivo(
                    paciente: paciente,
                    vinculado: vinculado,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: _pestana,
                children: [
                  _PestanaHistorial(paciente: paciente),
                  _PestanaHorario(paciente: paciente),
                  _PestanaEstadisticas(paciente: paciente),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _pestana,
          onTap: (i) => setState(() => _pestana = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.medication),
              label: 'Historial',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.schedule),
              label: 'Horario',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'Estadísticas',
            ),
          ],
        ),
      ),
    );
  }
}

/// Pestaña "Horario": lo que ya se veía en el detalle del paciente, la lista de
/// tratamientos con sus horas y días más el resumen de estado reciente.
class _PestanaHorario extends StatefulWidget {
  final Paciente paciente;
  const _PestanaHorario({required this.paciente});

  @override
  State<_PestanaHorario> createState() => _PestanaHorarioState();
}

class _PestanaHorarioState extends State<_PestanaHorario> {
  int _reintento = 0;

  Paciente get paciente => widget.paciente;

  void _reintentar() => setState(() => _reintento++);

  @override
  Widget build(BuildContext context) {
    // Deja espacio para el botón flotante "Nuevo medicamento" (56 dp) más
    // 24 dp de separación y el área segura inferior, para que la última tarjeta
    // no quede tapada al hacer scroll hasta el final.
    final paddingInferior = 56.0 + 24.0 + MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm + paddingInferior,
      ),
      children: [
        _AvisoSinTomas(pacienteId: paciente.id),
        Text(
          'Medicamentos',
          style: AppType.title.copyWith(color: AppColors.onGreen),
        ),
        const SizedBox(height: AppSpacing.xs),
        _listaTratamientos(),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Estado reciente',
          style: AppType.title.copyWith(color: AppColors.onGreen),
        ),
        const SizedBox(height: AppSpacing.xs),
        _EstadoReciente(pacienteId: paciente.id),
      ],
    );
  }

  Widget _listaTratamientos() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('tratamientos-$_reintento'),
      stream: FirebaseFirestore.instance
          .collection('tratamientos')
          .where('pacienteId', isEqualTo: paciente.id)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EstadoError(
            mensaje: mensajeErrorAmigable(
              snap.error!,
              contexto: 'Error cargando tratamientos del paciente',
            ),
            onReintentar: _reintentar,
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const EstadoCargando(texto: 'Cargando medicamentos...');
        }
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        final tratamientos = snap.data!.docs
            .map(
              (d) =>
                  Tratamiento.fromMap(d.id, d.data() as Map<String, dynamic>),
            )
            .toList();
        if (tratamientos.isEmpty) {
          return const EstadoVacio(
            icono: Icons.medication,
            titulo: 'Aún no hay medicamentos',
            mensaje: 'Agrega el primero con el botón de abajo.',
          );
        }
        final ahora = DateTime.now();
        return Column(
          children: tratamientos.map((t) {
            return TarjetaMedicamento(
              tratamiento: t,
              ahora: ahora,
              onEliminar: () => _confirmarEliminar(context, t),
              onTap: () {
                Navigator.of(context).push(
                  AppPageRoute(
                    builder: (_) => EditarTratamientoScreen(
                      pacienteId: paciente.id,
                      tratamiento: t,
                      esNuevo: false,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _confirmarEliminar(
    BuildContext context,
    Tratamiento tratamiento,
  ) async {
    final ok = await mostrarDialogoAccionDelicada(
      context,
      titulo: 'Eliminar medicamento',
      mensaje:
          '¿Eliminar ${tratamiento.nombreMedicamento}? '
          'Esta acción no se puede deshacer.',
      textoAccion: 'Eliminar',
      icono: Icons.delete_outline,
    );
    if (!ok || !context.mounted) return;

    try {
      // Primero se cancelan las notificaciones: si el borrado en Firestore
      // falla, el tratamiento sigue existiendo pero nunca queda una alarma o
      // recordatorio huérfano para un medicamento que ya no está.
      await NotificacionesService().cancelarNotificacionesDeTratamiento(
        tratamientoId: tratamiento.id,
        horarios: tratamiento.horarios,
      );
      await FirestoreService().eliminarTratamiento(tratamiento.id);
      SincronizacionPacienteService().programarEnvio(widget.paciente.id);

      if (context.mounted) {
        HapticFeedback.lightImpact();
        mostrarSnackExito(
          context,
          '${tratamiento.nombreMedicamento} eliminado.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(e, contexto: 'Error eliminando tratamiento'),
        );
      }
    }
  }
}

/// Respaldo del push de "5 días sin tomas" cuando el paciente no abrió la app.
///
/// Recalcula lo mismo que [AlertaSinTomasService] con los tratamientos y los
/// registros del paciente. No envía FCM: solo pinta un aviso visible en el
/// detalle del cuidador.
class _AvisoSinTomas extends StatefulWidget {
  final String pacienteId;
  const _AvisoSinTomas({required this.pacienteId});

  @override
  State<_AvisoSinTomas> createState() => _AvisoSinTomasState();
}

class _AvisoSinTomasState extends State<_AvisoSinTomas> {
  final FirestoreService _fs = FirestoreService();
  late final Stream<List<Tratamiento>> _tratamientos;
  late final Future<List<RegistroToma>> _registros;

  @override
  void initState() {
    super.initState();
    _tratamientos = _fs.streamTratamientosDePaciente(widget.pacienteId);

    // 35 días cubren de sobra los últimos 5 días programados incluso con un
    // horario de una vez por semana. Se lee una sola vez al abrir el detalle;
    // es un respaldo, no el mecanismo principal.
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    _registros = _fs.getRegistrosEnRango(
      widget.pacienteId,
      DateTime(hoy.year, hoy.month, hoy.day - 35),
      DateTime(hoy.year, hoy.month, hoy.day + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Tratamiento>>(
      stream: _tratamientos,
      builder: (context, tratSnap) {
        final tratamientos = tratSnap.data ?? const <Tratamiento>[];
        if (tratamientos.isEmpty) return const SizedBox.shrink();

        return FutureBuilder<List<RegistroToma>>(
          future: _registros,
          builder: (context, regSnap) {
            if (regSnap.connectionState == ConnectionState.waiting ||
                regSnap.hasError) {
              return const SizedBox.shrink();
            }
            final registros = regSnap.data ?? const <RegistroToma>[];
            final ahora = DateTime.now();
            final alertas = tratamientos
                .where(
                  (t) => AlertaSinTomasService.hayAlerta(
                    tratamiento: t,
                    registros: registros,
                    ahora: ahora,
                  ),
                )
                .toList();
            if (alertas.isEmpty) return const SizedBox.shrink();

            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              color: AppColors.warning.withValues(alpha: 0.10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                side: const BorderSide(color: AppColors.warning, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '5 días sin tomas',
                            style: AppType.label.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final t in alertas)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${t.nombreMedicamento}: sin tomas '
                                'confirmadas en los últimos 5 días programados.',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Pestaña "Historial": los últimos registros de toma del paciente, del más
/// reciente al más antiguo.
///
/// Cada fila cruza el `tratamientoId` del registro con el nombre del
/// medicamento, igual que hace el panel de actividad del dashboard, y muestra la
/// hora **programada** con un badge de color según cómo terminó la toma.
///
/// Son [Stream] y por eso van en un `StatefulWidget` a propósito: las tres
/// pestañas viven en un `IndexedStack`, así que este widget se reconstruye en
/// cada cambio de pestaña y, de crear los streams en `build`, cada `StreamBuilder`
/// se volvería a suscribir y a releer Firestore de cero.
class _PestanaHistorial extends StatefulWidget {
  final Paciente paciente;
  const _PestanaHistorial({required this.paciente});

  @override
  State<_PestanaHistorial> createState() => _PestanaHistorialState();
}

class _PestanaHistorialState extends State<_PestanaHistorial> {
  /// Tope de filas. No es scroll infinito a propósito: el historial es
  /// orientativo y cada fila ya trae el nombre del medicamento, así que más de
  /// esto no aporta y encarece la lectura.
  static const int _limite = 50;

  final FirestoreService _fs = FirestoreService();
  late Stream<List<Tratamiento>> _tratamientos;
  late Stream<List<RegistroToma>> _registros;
  int _reintento = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _tratamientos = _fs.streamTratamientosDePaciente(widget.paciente.id);
    _registros = _fs.streamRegistrosDePaciente(
      widget.paciente.id,
      limite: _limite,
    );
  }

  void _reintentar() {
    setState(() {
      _reintento++;
      _cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Tratamiento>>(
      key: ValueKey('historial-tratamientos-$_reintento'),
      stream: _tratamientos,
      builder: (context, tratSnap) {
        if (tratSnap.connectionState == ConnectionState.waiting) {
          return const EstadoCargando(texto: 'Cargando historial...');
        }
        if (tratSnap.hasError) {
          return EstadoError(
            mensaje: mensajeErrorAmigable(
              tratSnap.error!,
              contexto: 'Error cargando tratamientos del historial',
            ),
            onReintentar: _reintentar,
          );
        }
        // Se resuelve el nombre una sola vez por lista en vez de un fetch por
        // fila, y con un stream propio para que un medicamento renombrado se
        // refleje sin recargar.
        final nombres = <String, String>{
          for (final t in tratSnap.data ?? const <Tratamiento>[])
            t.id: t.nombreMedicamento,
        };

        return StreamBuilder<List<RegistroToma>>(
          key: ValueKey('historial-registros-$_reintento'),
          stream: _registros,
          builder: (context, snap) {
            if (snap.hasError) {
              return EstadoError(
                mensaje: mensajeErrorAmigable(
                  snap.error!,
                  contexto: 'Error cargando registros del historial',
                ),
                onReintentar: _reintentar,
              );
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const EstadoCargando(texto: 'Cargando historial...');
            }
            final registros = snap.data ?? const <RegistroToma>[];
            if (registros.isEmpty) {
              return const EstadoVacio(
                icono: Icons.history,
                titulo: 'Aún no hay tomas registradas',
                mensaje:
                    'Cuando el paciente confirme una toma, aparecerá aquí.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: registros.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) => _FilaHistorial(
                registro: registros[i],
                // Borrar un tratamiento no toca los registros ya escritos, así
                // que un `tratamientoId` puede no resolver: la fila tiene que
                // seguir siendo legible en vez de romper.
                nombreMedicamento:
                    nombres[registros[i].tratamientoId] ??
                    'Medicamento eliminado',
              ),
            );
          },
        );
      },
    );
  }
}

/// Una toma en el historial: medicamento, día y hora programada, a qué hora se
/// confirmó (si se confirmó) y el badge de estado.
class _FilaHistorial extends StatelessWidget {
  final RegistroToma registro;
  final String nombreMedicamento;
  const _FilaHistorial({
    required this.registro,
    required this.nombreMedicamento,
  });

  @override
  Widget build(BuildContext context) {
    final (etiqueta, color, icono) = _estiloEstado(registro.estado);
    final confirmada = horaConfirmacionCorta(registro);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombreMedicamento,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etiquetaProgramada(registro),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (confirmada.isNotEmpty)
                    Text(
                      'Confirmada a las $confirmada',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _BadgeEstado(etiqueta: etiqueta, color: color),
          ],
        ),
      ),
    );
  }
}

/// Píldora de estado: color + rótulo.
///
/// El color viene del rol de `AppColors` correspondiente al estado, nunca de un
/// literal: así "tardó" se ve igual en el historial y en cualquier otro lado.
class _BadgeEstado extends StatelessWidget {
  final String etiqueta;
  final Color color;
  const _BadgeEstado({required this.etiqueta, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        etiqueta,
        style: const TextStyle(
          color: AppColors.onAccent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Estilo del estado: (rótulo, color, ícono).
///
/// El rótulo se deriva de [EstadoTomaExt.nombre] — la misma fuente de verdad que
/// persiste el estado en Firestore — en vez de escribir los literales a mano, que
/// es lo que obliga a tocarlos en cada lado al agregar un estado. Solo se
/// capitaliza la primera letra para que se lea como etiqueta y no como dato.
(String, Color, IconData) _estiloEstado(EstadoToma e) {
  final (color, icono) = switch (e) {
    EstadoToma.tomada => (AppColors.accent, Icons.check_circle),
    EstadoToma.tardia => (AppColors.amber, Icons.timer_outlined),
    EstadoToma.pospuesta => (AppColors.warning, Icons.snooze),
    EstadoToma.olvidada => (AppColors.error, Icons.cancel),
    EstadoToma.pendiente => (AppColors.textSecondary, Icons.schedule),
  };
  final nombre = e.nombre;
  return ('${nombre[0].toUpperCase()}${nombre.substring(1)}', color, icono);
}

/// Resumen compacto del celular que tiene las alarmas del paciente.
class _CardCelularPaciente extends StatelessWidget {
  final EstadoDispositivo? estado;

  const _CardCelularPaciente({required this.estado});

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final aviso = necesitaAvisoAlarmas(estado, ahora);
    final ultima = textoUltimaSincronizacion(
      estado?.ultimaSincronizacion,
      ahora,
    );
    final notificacionesOk = estado?.notificacionesPermitidas == true;
    final bateriaOk = estado?.bateriaSinRestricciones == true;

    return Card(
      margin: EdgeInsets.zero,
      color: aviso
          ? AppColors.warning.withValues(alpha: 0.08)
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: aviso ? AppColors.warning : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.smartphone,
                  color: aviso ? AppColors.warning : AppColors.accent,
                  size: AppSizes.iconSmall,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Celular del paciente',
                    style: AppType.label.copyWith(
                      color: AppColors.onGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (aviso)
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: AppSizes.iconSmall,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Última conexión: $ultima',
              style: AppType.body.copyWith(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              'Alarmas programadas: ${estado?.alarmasProgramadas ?? 0}',
              style: AppType.body.copyWith(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              children: [
                _IndicadorCelular(
                  ok: notificacionesOk,
                  texto: estado == null
                      ? 'Sin reporte del celular'
                      : notificacionesOk
                      ? 'Notificaciones permitidas'
                      : 'Notificaciones bloqueadas',
                ),
                if (estado != null && !bateriaOk)
                  const _IndicadorCelular(
                    ok: false,
                    texto: 'Batería con restricciones',
                  ),
              ],
            ),
            if (aviso) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                mensajeAlarmasNoSuenan,
                style: AppType.label.copyWith(color: AppColors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IndicadorCelular extends StatelessWidget {
  final bool ok;
  final String texto;

  const _IndicadorCelular({required this.ok, required this.texto});

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.accent : AppColors.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.warning_amber_rounded,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: AppType.label.copyWith(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BtnDesvincular extends StatelessWidget {
  final Paciente paciente;
  const _BtnDesvincular({required this.paciente});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _confirmar(context),
      style: TextButton.styleFrom(foregroundColor: AppColors.error),
      icon: const Icon(Icons.link_off),
      label: const Text('Desvincular dispositivo'),
    );
  }

  Future<void> _confirmar(BuildContext context) async {
    final ok = await mostrarDialogoAccionDelicada(
      context,
      titulo: 'Desvincular dispositivo',
      mensaje:
          'El paciente ya no podrá ver sus medicamentos en este teléfono. '
          'Para volver a vincularlo, tendrá que compartirle el código.',
      textoAccion: 'Desvincular',
      icono: Icons.link_off,
    );
    if (!ok || !context.mounted) return;
    try {
      await FirestoreService().desvincularDispositivo(paciente.id);
      if (context.mounted) {
        HapticFeedback.lightImpact();
        mostrarSnackExito(
          context,
          'Dispositivo desvinculado. El paciente deberá reingresar el código '
          'para volver a vincularse.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(e, contexto: 'Error desvinculando dispositivo'),
        );
      }
    }
  }
}

class _FichaPaciente extends StatelessWidget {
  final Paciente paciente;
  const _FichaPaciente({required this.paciente});

  @override
  Widget build(BuildContext context) {
    // Edad, condición, contacto y foto son opcionales: se omite lo que no se
    // informe, así que los pacientes creados antes de que existieran los campos
    // muestran solo el nombre, sin placeholders ni filas vacías.
    final edad = paciente.edad;
    final condicion = paciente.condicion?.trim();
    final contacto = paciente.contactoEmergencia?.trim();
    final telefono = normalizarTelefonoEmergencia(contacto);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvatarPaciente(paciente: paciente, radio: 40),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                paciente.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.title.copyWith(color: AppColors.onGreen),
              ),
              if (edad != null) ...[
                const SizedBox(height: 2),
                Text(
                  '$edad ${edad == 1 ? 'año' : 'años'}',
                  style: AppType.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
              if (condicion != null && condicion.isNotEmpty) ...[
                const SizedBox(height: 6),
                ChipCondicion(texto: condicion),
              ],
              if (contacto != null && contacto.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  label: 'Contacto de emergencia: $contacto',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Emergencias: $contacto',
                          style: AppType.body.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (telefono != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            abrirMarcadorTelefono(context, telefono),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onGreen,
                          side: const BorderSide(color: AppColors.accent),
                          minimumSize: const Size(0, AppSizes.minTouch),
                        ),
                        icon: const Icon(Icons.call, size: AppSizes.iconSmall),
                        label: const Text('Llamar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: telefono),
                          );
                          if (context.mounted) {
                            mostrarSnackInfo(context, 'Número copiado');
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onGreen,
                          side: const BorderSide(color: AppColors.accent),
                          minimumSize: const Size(0, AppSizes.minTouch),
                        ),
                        icon: const Icon(Icons.copy, size: AppSizes.iconSmall),
                        label: const Text('Copiar'),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SeccionVinculacionDispositivo extends StatefulWidget {
  final Paciente paciente;
  final bool vinculado;

  const SeccionVinculacionDispositivo({
    super.key,
    required this.paciente,
    required this.vinculado,
  });

  @override
  State<SeccionVinculacionDispositivo> createState() =>
      _SeccionVinculacionDispositivoState();
}

class _SeccionVinculacionDispositivoState
    extends State<SeccionVinculacionDispositivo> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _vinculo;
  bool _expandido = false;
  bool _generando = false;

  String get _codigo => widget.paciente.codigoVinculacion.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _escucharVinculo();
  }

  @override
  void didUpdateWidget(covariant SeccionVinculacionDispositivo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paciente.codigoVinculacion !=
        widget.paciente.codigoVinculacion) {
      _escucharVinculo();
    }
  }

  void _escucharVinculo() {
    final codigo = _codigo;
    if (codigo.isEmpty) {
      _vinculo = null;
      return;
    }
    try {
      _vinculo = FirebaseFirestore.instance
          .collection('vinculos')
          .doc(codigo)
          .snapshots();
    } catch (_) {
      // En entornos sin Firebase inicializado (p. ej. pruebas de widget) el
      // stream no se puede abrir; se muestra "Sin vencimiento" en su lugar.
      _vinculo = null;
    }
  }

  Future<void> _copiar() async {
    if (_codigo.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _codigo));
    HapticFeedback.lightImpact();
    if (mounted) mostrarSnackInfo(context, 'Código copiado');
  }

  Future<void> _generar() async {
    if (_generando || widget.vinculado) return;
    final ok = await mostrarDialogoAccionDelicada(
      context,
      titulo: 'Generar código nuevo',
      mensaje:
          'El código actual dejará de funcionar. El paciente tendrá que usar '
          'el nuevo para vincularse.',
      textoAccion: 'Generar',
      icono: Icons.refresh,
    );
    if (!ok || !mounted) return;

    setState(() => _generando = true);
    try {
      final nuevo = await VinculacionService().regenerarCodigoVinculacion(
        widget.paciente.id,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      mostrarSnackExito(context, 'Código nuevo generado: $nuevo');
    } catch (e) {
      if (mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(e, contexto: 'Error generando código'),
        );
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _vinculo,
      builder: (context, snap) {
        final expiraEn = _fechaDeExpiracion(snap.data?.data()?['expiraEn']);
        final ahora = DateTime.now();
        final resumen = resumenVinculacion(
          vinculado: widget.vinculado,
          expiraCodigo: expiraEn,
          ahora: ahora,
          estadoDispositivo: widget.paciente.estadoDispositivo,
        );

        return Card(
          color: AppColors.primary,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      widget.vinculado ? Icons.link : Icons.link_off,
                      color: widget.vinculado
                          ? AppColors.accent
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vinculación y dispositivo',
                            style: AppType.label.copyWith(
                              color: AppColors.onGreen,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            resumen.texto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.body.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (resumen.advertencia)
                      Semantics(
                        label:
                            'Advertencia: el celular del paciente puede no '
                            'tener las alarmas activas',
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.warning,
                            size: AppSizes.iconSmall,
                          ),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() => _expandido = !_expandido),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: AppType.label,
                      ),
                      icon: Icon(
                        _expandido
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: AppSizes.iconSmall,
                      ),
                      label: Text(_expandido ? 'Ocultar' : 'Mostrar'),
                    ),
                  ],
                ),
                if (_expandido) ...[
                  const Divider(height: 20),
                  Text(
                    widget.vinculado
                        ? 'Estado: dispositivo vinculado'
                        : 'Estado: sin vincular',
                    style: AppType.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _codigo.isEmpty ? 'Sin código' : _codigo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onGreen,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar código',
                        onPressed: _codigo.isEmpty ? null : _copiar,
                        icon: const Icon(Icons.copy),
                        color: AppColors.onGreen,
                      ),
                    ],
                  ),
                  _vencimiento(snap, ahora),
                  const SizedBox(height: AppSpacing.xs),
                  if (!widget.vinculado)
                    TextButton.icon(
                      onPressed: _generando ? null : _generar,
                      icon: const Icon(Icons.refresh, size: AppSizes.iconSmall),
                      label: Text(
                        _generando ? 'Generando...' : 'Generar código nuevo',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onGreen,
                      ),
                    ),
                  if (!widget.vinculado)
                    const Text(
                      'Compártelo con el paciente para que se vincule.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  if (widget.vinculado) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _CardCelularPaciente(
                      estado: widget.paciente.estadoDispositivo,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _BtnDesvincular(paciente: widget.paciente),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _vencimiento(
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
    DateTime ahora,
  ) {
    if (_vinculo == null) {
      return const Text(
        'Sin vencimiento',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    if (snap.hasError) {
      return const Text(
        'No se pudo consultar el vencimiento',
        style: TextStyle(color: AppColors.error),
      );
    }
    if (snap.connectionState == ConnectionState.waiting) {
      return const Text(
        'Consultando vencimiento...',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }

    final expiraEn = _fechaDeExpiracion(snap.data?.data()?['expiraEn']);
    final estado = estadoDelCodigo(expiraEn, ahora);
    final texto = textoVencimientoCodigo(expiraEn, ahora);
    return Text(
      texto,
      style: TextStyle(
        color: estado == EstadoCodigoVinculacion.vencido
            ? AppColors.error
            : AppColors.textSecondary,
        fontWeight: estado == EstadoCodigoVinculacion.vencido
            ? FontWeight.bold
            : null,
      ),
    );
  }
}

DateTime? _fechaDeExpiracion(Object? valor) {
  if (valor is Timestamp) return valor.toDate();
  if (valor is DateTime) return valor;
  return null;
}

class _EstadoReciente extends StatefulWidget {
  final String pacienteId;
  const _EstadoReciente({required this.pacienteId});

  @override
  State<_EstadoReciente> createState() => _EstadoRecienteState();
}

class _EstadoRecienteState extends State<_EstadoReciente> {
  int _reintento = 0;

  void _reintentar() => setState(() => _reintento++);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('estado-reciente-$_reintento'),
      stream: FirebaseFirestore.instance
          .collection('registrosToma')
          .where('pacienteId', isEqualTo: widget.pacienteId)
          .orderBy('horaProgramada', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EstadoError(
            mensaje: mensajeErrorAmigable(
              snap.error!,
              contexto: 'Error cargando estado reciente',
            ),
            onReintentar: _reintentar,
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const EstadoCargando(texto: 'Cargando estado...');
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const EstadoVacio(
            icono: Icons.history,
            titulo: 'Aún no hay tomas registradas',
            mensaje: 'Cuando el paciente confirme una toma, aparecerá aquí.',
          );
        }
        // Los duplicados viejos de una misma ranura no deben inflar el panel.
        final registros = RegistrosToma.deduplicarPorRanura(
          snap.data!.docs.map(
            (d) => RegistroToma.fromMap(d.id, d.data() as Map<String, dynamic>),
          ),
        );
        int tomadas = 0, tardias = 0, olvidadas = 0;
        for (final r in registros) {
          if (r.estado == EstadoToma.tomada) tomadas++;
          if (r.estado == EstadoToma.tardia) tardias++;
          if (r.estado == EstadoToma.olvidada) olvidadas++;
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _FilaEstado(
                  icono: Icons.check_circle,
                  color: AppColors.accent,
                  texto: 'Tomadas',
                  cantidad: tomadas,
                ),
                _FilaEstado(
                  icono: Icons.timer_outlined,
                  color: AppColors.amber,
                  texto: 'Tardías',
                  cantidad: tardias,
                ),
                _FilaEstado(
                  icono: Icons.cancel,
                  color: AppColors.error,
                  texto: 'Olvidadas',
                  cantidad: olvidadas,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilaEstado extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;
  final int cantidad;
  const _FilaEstado({
    required this.icono,
    required this.color,
    required this.texto,
    required this.cantidad,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 16))),
          Text(
            '$cantidad',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Pestaña "Estadísticas": adherencia del paciente.
///
/// Es `StatefulWidget` por la misma razón que [_PestanaHistorial]: las tres
/// pestañas viven en un `IndexedStack`, así que construir los streams dentro de
/// `build` re-suscribiría y re-leería Firestore en cada cambio de pestaña.
///
/// Los cálculos NO viven aquí: [resumenCumplimiento] es puro y está en
/// `lib/utils/estadisticas.dart`, con sus propios tests sin Firebase. Esta
/// pantalla solo lee el resultado y lo dibuja.
class _PestanaEstadisticas extends StatefulWidget {
  final Paciente paciente;
  const _PestanaEstadisticas({required this.paciente});

  @override
  State<_PestanaEstadisticas> createState() => _PestanaEstadisticasState();
}

class _PestanaEstadisticasState extends State<_PestanaEstadisticas> {
  /// Tope de registros leídos. Es un límite de transporte, no de Exactitud: si
  /// se alcanza, la ventana de 30 días puede estar incompleta y por eso la UI
  /// lo avisa en vez de presentar el número como definitivo.
  static const int _limite = 500;

  /// Ventana titular: es la que se lee "a ojo" y la única diaria.
  static const int _diasTitular = 7;

  /// Ventana secundaria, más larga para que la cifra se estabilice.
  static const int _diasSecundario = 30;

  final FirestoreService _fs = FirestoreService();
  late Future<List<RegistroToma>> _registros;
  late Stream<List<Tratamiento>> _tratamientos;
  int _reintento = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _registros = _fs.getRegistrosRecientes(widget.paciente.id, limite: _limite);
    _tratamientos = _fs.streamTratamientosDePaciente(widget.paciente.id);
  }

  void _reintentar() {
    setState(() {
      _reintento++;
      _cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RegistroToma>>(
      key: ValueKey('estadisticas-registros-$_reintento'),
      future: _registros,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const EstadoCargando(texto: 'Cargando estadísticas...');
        }
        if (snap.hasError) {
          return EstadoError(
            mensaje: mensajeErrorAmigable(
              snap.error!,
              contexto: 'Error cargando registros de estadísticas',
            ),
            onReintentar: _reintentar,
          );
        }
        final registros = snap.data ?? const <RegistroToma>[];

        return StreamBuilder<List<Tratamiento>>(
          key: ValueKey('estadisticas-tratamientos-$_reintento'),
          stream: _tratamientos,
          builder: (context, tratSnap) {
            if (tratSnap.hasError) {
              return EstadoError(
                mensaje: mensajeErrorAmigable(
                  tratSnap.error!,
                  contexto: 'Error cargando tratamientos de estadísticas',
                ),
                onReintentar: _reintentar,
              );
            }
            if (tratSnap.connectionState == ConnectionState.waiting &&
                !tratSnap.hasData) {
              return const EstadoCargando(texto: 'Cargando estadísticas...');
            }
            final tratamientos = tratSnap.data ?? const <Tratamiento>[];
            final ahora = DateTime.now();

            final titular = resumenCumplimiento(
              tratamientos: tratamientos,
              registros: registros,
              ahora: ahora,
              dias: _diasTitular,
            );
            final secundario = resumenCumplimiento(
              tratamientos: tratamientos,
              registros: registros,
              ahora: ahora,
              dias: _diasSecundario,
            );

            if (tratamientos.isEmpty || !titular.hayDatos) {
              return const EstadoVacio(
                icono: Icons.bar_chart,
                titulo: 'Aún no hay estadísticas',
                mensaje: 'Cuando el paciente tenga medicamentos y tomas, verás aquí su cumplimiento.',
              );
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.sm),
              children: [
                _CardAdherencia(resumen: titular, dias: _diasTitular),
                const SizedBox(height: AppSpacing.xs),
                _CardBarraApilada(resumen: titular),
                const SizedBox(height: AppSpacing.xs),
                _CardTiraSemanal(resumen: titular),
                const SizedBox(height: AppSpacing.xs),
                _CardVentanaLarga(resumen: secundario, dias: _diasSecundario),
                const SizedBox(height: AppSpacing.xs),
                _CardRacha(resumen: titular),
                if (registros.length >= _limite) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const _AvisoTruncado(),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// Adherencia de la ventana titular, en grande.
///
/// Muestra `null` como "Sin datos" y no como `0%`: un paciente sin horarios
/// y un paciente que falló todo no son lo mismo, y confundirlos sería una
/// mentira.
class _CardAdherencia extends StatelessWidget {
  final ResumenCumplimiento resumen;
  final int dias;

  const _CardAdherencia({required this.resumen, required this.dias});

  @override
  Widget build(BuildContext context) {
    final pct = resumen.porcentajeATiempo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Adherencia de los últimos $dias días',
                style: AppType.label.copyWith(color: AppColors.onGreen),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              label: pct == null
                  ? 'Sin datos de adherencia'
                  : 'Adherencia del ${pct.round()} por ciento',
              excludeSemantics: true,
              child: Text(
                pct == null ? '—' : '${pct.round()}%',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
            ),
            Text(
              pct == null
                  ? 'Sin datos: el paciente no tiene horarios con dosis.'
                  : 'de las ${resumen.esperadas} tomas esperadas se tomaron a tiempo.',
              style: AppType.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra apilada: una fila por estado, en el mismo orden de gravedad que
/// `EstadoDia` para que el cuidado se lea de izquierda a derecha.
class _CardBarraApilada extends StatelessWidget {
  final ResumenCumplimiento resumen;

  const _CardBarraApilada({required this.resumen});

  @override
  Widget build(BuildContext context) {
    if (!resumen.hayDatos) return const SizedBox.shrink();

    final total = resumen.esperadas.toDouble();
    // El peso de cada segmento se pondera ×1000 y se redondea: `Expanded` pide
    // enteros y dos segmentos de 0.4% terminarían en flex 0, que revienta.
    int peso(int valor) => ((valor / total) * 1000).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Cómo se repartieron las tomas',
                style: AppType.label.copyWith(color: AppColors.onGreen),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    if (resumen.aTiempo > 0)
                      Expanded(
                        flex: peso(resumen.aTiempo),
                        child: Container(color: AppColors.accent),
                      ),
                    if (resumen.tardias > 0)
                      Expanded(
                        flex: peso(resumen.tardias),
                        child: Container(color: AppColors.amber),
                      ),
                    if (resumen.olvidadas > 0)
                      Expanded(
                        flex: peso(resumen.olvidadas),
                        child: Container(color: AppColors.error),
                      ),
                    if (resumen.sinRegistro > 0)
                      Expanded(
                        flex: peso(resumen.sinRegistro),
                        child: Container(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _Leyenda(
                  color: AppColors.accent,
                  texto: 'A tiempo',
                  valor: resumen.aTiempo,
                ),
                _Leyenda(
                  color: AppColors.amber,
                  texto: 'Tardías',
                  valor: resumen.tardias,
                ),
                _Leyenda(
                  color: AppColors.error,
                  texto: 'Olvidadas',
                  valor: resumen.olvidadas,
                ),
                _Leyenda(
                  color: AppColors.textSecondary,
                  texto: 'Sin registro',
                  valor: resumen.sinRegistro,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Un cuadro por día de la ventana, coloreado por el peor estado del día.
///
/// El peor y no el promedio a propósito: un día con una toma de las tres es un
/// día con una falta, y promediar lo escondería.
class _CardTiraSemanal extends StatelessWidget {
  final ResumenCumplimiento resumen;

  const _CardTiraSemanal({required this.resumen});

  static const List<String> _iniciales = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    if (resumen.dias.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Últimos 7 días',
                style: AppType.label.copyWith(color: AppColors.onGreen),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cada cuadro muestra el peor estado del día.',
              style: AppType.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                for (final d in resumen.dias)
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 44),
                        child: _CuadroDia(
                          inicial: _iniciales[d.dia.weekday - 1],
                          dia: d.dia,
                          estado: d.estado,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Un día de la tira. `sinDosis` se dibuja apagado y neutro: no fue un logro
/// ni un fallo, y ponerlo en rojo delataría un horario que el paciente nunca
/// tuvo.
class _CuadroDia extends StatelessWidget {
  final String inicial;
  final DateTime dia;
  final EstadoDia estado;

  const _CuadroDia({
    required this.inicial,
    required this.dia,
    required this.estado,
  });

  static const Map<int, String> _diasLargos = {
    1: 'Lunes',
    2: 'Martes',
    3: 'Miércoles',
    4: 'Jueves',
    5: 'Viernes',
    6: 'Sábado',
    7: 'Domingo',
  };

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) {
      EstadoDia.diaPerfecto => AppColors.accent,
      EstadoDia.conTardias => AppColors.amber,
      EstadoDia.diaConFaltas => AppColors.error,
      EstadoDia.sinDosis => AppColors.border,
    };
    final ahora = DateTime.now();
    final hoy =
        dia.year == ahora.year &&
        dia.month == ahora.month &&
        dia.day == ahora.day;
    final estadoTexto = switch (estado) {
      EstadoDia.diaPerfecto => 'día perfecto',
      EstadoDia.conTardias => 'día con tomas tardías',
      EstadoDia.diaConFaltas => 'día con faltas',
      EstadoDia.sinDosis => 'sin dosis programadas',
    };

    return Semantics(
      label: '${_diasLargos[dia.weekday] ?? 'Día'} ${dia.day}: $estadoTexto',
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: estado == EstadoDia.sinDosis ? 0.4 : 0.18,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: hoy ? 2 : 1),
            ),
            alignment: Alignment.center,
            child: Text(
              inicial,
              style: TextStyle(
                color: AppColors.onGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${dia.day}',
            style: TextStyle(
              fontSize: 11,
              color: hoy ? AppColors.onGreen : AppColors.textSecondary,
              fontWeight: hoy ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ventana larga. Se rotula "aproximado" a propósito: 30 días dependen de
/// Treatments que pueden haber cambiado, y de una reconciliación que solo
/// corre si el paciente abrió la app.
class _CardVentanaLarga extends StatelessWidget {
  final ResumenCumplimiento resumen;
  final int dias;

  const _CardVentanaLarga({required this.resumen, required this.dias});

  @override
  Widget build(BuildContext context) {
    final pct = resumen.porcentajeATiempo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.date_range, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Adherencia de los últimos $dias días',
                      style: AppType.label.copyWith(color: AppColors.onGreen),
                    ),
                  ),
                  Text(
                    'Valor aproximado',
                    style: AppType.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: pct == null
                  ? 'Sin datos de adherencia'
                  : 'Adherencia aproximada del ${pct.round()} por ciento',
              excludeSemantics: true,
              child: Text(
                pct == null ? '—' : '${pct.round()}%',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Racha de días consecutivos sin fallos.
class _CardRacha extends StatelessWidget {
  final ResumenCumplimiento resumen;

  const _CardRacha({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final racha = resumen.racha;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Días seguidos a tiempo',
                      style: AppType.label.copyWith(color: AppColors.onGreen),
                    ),
                  ),
                  Text(
                    'Días completos, sin contar hoy',
                    style: AppType.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: 'Racha de $racha días seguidos a tiempo',
              excludeSemantics: true,
              child: Text(
                '$racha',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso de que la lectura se topó con el límite de registros.
///
/// Sin esto la ventana de 30 días parecería exacta cuando en realidad puede
/// estar incompleta por un corte de transporte.
class _AvisoTruncado extends StatelessWidget {
  const _AvisoTruncado();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Hay demasiados registros: las cifras de 30 días pueden estar '
            'incompletas.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Cuadro de color + conteo. Se oculta solo cuando el estado no ocurrió, para
/// que la leyenda no enseñe ceros.
class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  final int valor;

  const _Leyenda({
    required this.color,
    required this.texto,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    if (valor == 0) return const SizedBox.shrink();
    return Semantics(
      label: '$texto: $valor',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$texto: $valor', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
