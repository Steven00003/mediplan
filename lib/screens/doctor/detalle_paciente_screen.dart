import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/paciente.dart';
import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../services/alerta_sin_tomas_service.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/etiqueta_toma.dart';
import '../../utils/estadisticas.dart';
import '../../utils/resumen_horario.dart';
import '../../utils/vigencia_tratamiento.dart';
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
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
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

  @override
  Widget build(BuildContext context) {
    final paciente = widget.paciente;
    final vinculado =
        paciente.dispositivoVinculadoId != null &&
        paciente.dispositivoVinculadoId!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(paciente.nombre)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditarTratamientoScreen(
                pacienteId: paciente.id,
                esNuevo: true,
              ),
            ),
          );
        },
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo medicamento'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                _FichaPaciente(paciente: paciente),
                const SizedBox(height: 16),
                _CardCodigo(paciente: paciente, vinculado: vinculado),
                if (vinculado) ...[
                  const SizedBox(height: 12),
                  _BtnDesvincular(paciente: paciente),
                ],
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
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.medication),
            label: 'Historial',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Horario'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Estadísticas',
          ),
        ],
      ),
    );
  }
}

/// Pestaña "Horario": lo que ya se veía en el detalle del paciente, la lista de
/// tratamientos con sus horas y días más el resumen de estado reciente.
class _PestanaHorario extends StatelessWidget {
  final Paciente paciente;
  const _PestanaHorario({required this.paciente});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AvisoSinTomas(pacienteId: paciente.id),
        const Text(
          'Medicamentos',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _listaTratamientos(),
        const SizedBox(height: 20),
        const Text(
          'Estado reciente',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _EstadoReciente(pacienteId: paciente.id),
      ],
    );
  }

  Widget _listaTratamientos() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tratamientos')
          .where('pacienteId', isEqualTo: paciente.id)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Text('Error al cargar medicamentos');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Sin medicamentos. Agrega el primero con el botón de abajo.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        final ahora = DateTime.now();
        return Column(
          children: tratamientos.map((t) {
            final (horasTexto, diasTexto) = resumenHorario(t);
            final finalizado = !VigenciaTratamiento.estaVigente(t, ahora);
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: (t.fotoBase64 != null && t.fotoBase64!.isNotEmpty)
                    ? CircleAvatar(
                        backgroundImage: MemoryImage(
                          ImagenService.decodificar(t.fotoBase64!)!,
                        ),
                      )
                    : const CircleAvatar(child: Icon(Icons.medication)),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.nombreMedicamento,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (finalizado)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Finalizado',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        '${t.dosis} dosis · $horasTexto',
                        // Opcional: solo aparece si se informó.
                        if (t.duracion != null && t.duracion!.isNotEmpty)
                          t.duracion!,
                      ].join(' · '),
                    ),
                    // Segunda línea solo en el caso de días compartidos, que es
                    // cuando no van ya pegados a cada hora.
                    if (diasTexto.isNotEmpty)
                      Text(
                        diasTexto,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: AppColors.error,
                      tooltip: 'Eliminar medicamento',
                      onPressed: () => _confirmarEliminar(context, t),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditarTratamientoScreen(
                        pacienteId: paciente.id,
                        tratamiento: t,
                        esNuevo: false,
                      ),
                    ),
                  );
                },
              ),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar medicamento'),
        content: Text(
          '¿Eliminar ${tratamiento.nombreMedicamento}? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      // Primero se cancelan las notificaciones: si el borrado en Firestore
      // falla, el tratamiento sigue existiendo pero nunca queda una alarma o
      // recordatorio huérfano para un medicamento que ya no está.
      await NotificacionesService().cancelarNotificacionesDeTratamiento(
        tratamientoId: tratamiento.id,
        horarios: tratamiento.horarios,
      );
      await FirestoreService().eliminarTratamiento(tratamiento.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tratamiento.nombreMedicamento} eliminado.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error eliminando tratamiento: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar el medicamento.')),
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
              margin: const EdgeInsets.only(bottom: 12),
              color: AppColors.error.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '5 días sin tomas',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
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
  late final Stream<List<Tratamiento>> _tratamientos;
  late final Stream<List<RegistroToma>> _registros;

  @override
  void initState() {
    super.initState();
    _tratamientos = _fs.streamTratamientosDePaciente(widget.paciente.id);
    _registros = _fs.streamRegistrosDePaciente(
      widget.paciente.id,
      limite: _limite,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Tratamiento>>(
      stream: _tratamientos,
      builder: (context, tratSnap) {
        if (tratSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tratSnap.hasError) {
          return _AvisoHistorial(tratSnap.error.toString());
        }
        // Se resuelve el nombre una sola vez por lista en vez de un fetch por
        // fila, y con un stream propio para que un medicamento renombrado se
        // refleje sin recargar.
        final nombres = <String, String>{
          for (final t in tratSnap.data ?? const <Tratamiento>[])
            t.id: t.nombreMedicamento,
        };

        return StreamBuilder<List<RegistroToma>>(
          stream: _registros,
          builder: (context, snap) {
            if (snap.hasError) {
              return _AvisoHistorial(snap.error.toString());
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final registros = snap.data ?? const <RegistroToma>[];
            if (registros.isEmpty) {
              return const _AvisoHistorial('Todavía no hay tomas registradas.');
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: registros.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
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

/// Mensaje centrado de la pestaña (sin datos o error).
class _AvisoHistorial extends StatelessWidget {
  final String texto;
  const _AvisoHistorial(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _BtnDesvincular extends StatelessWidget {
  final Paciente paciente;
  const _BtnDesvincular({required this.paciente});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _confirmar(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: BorderSide(color: AppColors.error),
        minimumSize: const Size.fromHeight(48),
      ),
      icon: const Icon(Icons.link_off),
      label: const Text('Desvincular dispositivo'),
    );
  }

  Future<void> _confirmar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular dispositivo'),
        content: const Text(
          'El paciente ya no podrá ver sus medicamentos en este teléfono. '
          'Para volver a vincularlo, tendrá que compartirle el código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await FirestoreService().desvincularDispositivo(paciente.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dispositivo desvinculado. El paciente deberá '
              'reingresar el código para volver a vincularse.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error desvinculando dispositivo: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo desvincular: $e')));
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
    final datos = <String>[
      if (paciente.edad != null)
        '${paciente.edad} ${paciente.edad == 1 ? 'año' : 'años'}',
      if (paciente.condicion != null && paciente.condicion!.isNotEmpty)
        paciente.condicion!,
    ];
    // Se decodifica primero y se comprueba antes de construir el MemoryImage:
    // un base64 corrupto devolvería null y el `!` reventaría la pantalla.
    final bytesFoto =
        (paciente.fotoBase64 != null && paciente.fotoBase64!.isNotEmpty)
        ? ImagenService.decodificar(paciente.fotoBase64!)
        : null;
    final tieneFoto = bytesFoto != null;
    final contacto = paciente.contactoEmergencia;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: AppColors.primary,
          foregroundImage: tieneFoto ? MemoryImage(bytesFoto) : null,
          child: tieneFoto
              ? null
              : const Icon(Icons.person, size: 40, color: AppColors.accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                paciente.nombre,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (datos.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  datos.join(' · '),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (contacto != null && contacto.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.phone,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        contacto,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CardCodigo extends StatelessWidget {
  final Paciente paciente;
  final bool vinculado;
  const _CardCodigo({required this.paciente, required this.vinculado});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  vinculado ? Icons.link : Icons.link_off,
                  color: vinculado ? AppColors.accent : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Text(
                  vinculado ? 'Dispositivo vinculado' : 'Código para unirse',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (!vinculado) ...[
              const SizedBox(height: 12),
              const Text(
                'Toca para copiar. El paciente lo ingresa en su celular (rol Paciente).',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: paciente.codigoVinculacion),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado')),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accent),
                  ),
                  child: Text(
                    paciente.codigoVinculacion,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onGreen,
                    ),
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

class _EstadoReciente extends StatelessWidget {
  final String pacienteId;
  const _EstadoReciente({required this.pacienteId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('registrosToma')
          .where('pacienteId', isEqualTo: pacienteId)
          .orderBy('horaProgramada', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No se pudo cargar el estado reciente.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'Todavía no hay tomas registradas.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        final docs = snap.data!.docs;
        int tomadas = 0, tardias = 0, olvidadas = 0;
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final estado = data['estado'] as String?;
          if (estado == 'tomó') tomadas++;
          if (estado == 'tardó') tardias++;
          if (estado == 'olvidó') olvidadas++;
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
  late final Future<List<RegistroToma>> _registros;
  late final Stream<List<Tratamiento>> _tratamientos;

  @override
  void initState() {
    super.initState();
    _registros = _fs.getRegistrosRecientes(widget.paciente.id, limite: _limite);
    _tratamientos = _fs.streamTratamientosDePaciente(widget.paciente.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RegistroToma>>(
      future: _registros,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(snap.error.toString(), textAlign: TextAlign.center),
            ),
          );
        }
        final registros = snap.data ?? const <RegistroToma>[];

        return StreamBuilder<List<Tratamiento>>(
          stream: _tratamientos,
          builder: (context, tratSnap) {
            if (tratSnap.connectionState == ConnectionState.waiting &&
                !tratSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
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

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CardAdherencia(resumen: titular, dias: _diasTitular),
                const SizedBox(height: 12),
                _CardBarraApilada(resumen: titular),
                const SizedBox(height: 12),
                _CardTiraSemanal(resumen: titular),
                const SizedBox(height: 12),
                _CardVentanaLarga(resumen: secundario, dias: _diasSecundario),
                const SizedBox(height: 12),
                _CardRacha(resumen: titular),
                if (registros.length >= _limite) ...[
                  const SizedBox(height: 12),
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
            Text(
              'Adherencia · últimos $dias días',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              pct == null ? '—' : '${pct.round()}%',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
            Text(
              pct == null
                  ? 'Sin datos: el paciente no tiene horarios con dosis.'
                  : 'de las ${resumen.esperadas} tomas esperadas se tomaron a tiempo.',
              style: const TextStyle(
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
            const Text(
              'Reparto de las tomas',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
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
                        child: Container(color: AppColors.warning),
                      ),
                    if (resumen.sinRegistro > 0)
                      Expanded(
                        flex: peso(resumen.sinRegistro),
                        child: Container(color: AppColors.error),
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
                  color: AppColors.warning,
                  texto: 'Olvidadas',
                  valor: resumen.olvidadas,
                ),
                _Leyenda(
                  color: AppColors.error,
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
            const Text(
              'Día por día',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cada cuadro toma el peor estado del día.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in resumen.dias)
                  _CuadroDia(
                    inicial: _iniciales[d.dia.weekday - 1],
                    dia: d.dia,
                    estado: d.estado,
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

    return Column(
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
                  Text(
                    'Adherencia · últimos $dias días',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Valor aproximado',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              pct == null ? '—' : '${pct.round()}%',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Racha a tiempo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Días seguidos completos, sin contar hoy',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$racha',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.warning,
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
    return Row(
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
    );
  }
}
