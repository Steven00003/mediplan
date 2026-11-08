import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../providers/app_state.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../services/local_store.dart';
import '../../services/notificaciones_service.dart';
import '../../services/omitidas_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/registros_toma.dart';
import '../../utils/vigencia_tratamiento.dart';
import 'alarma_screen.dart';

/// Pantalla principal del Paciente: "Medicamentos próximos".
///
/// Lista simple apoyada en íconos, navegación mínima. Comprueba cada 30
/// segundos si hay una toma pendiente que esté por vencerse y, en ese caso,
/// navega automáticamente a la pantalla de alarma.
class MedicamentosProximosScreen extends StatefulWidget {
  const MedicamentosProximosScreen({super.key});

  @override
  State<MedicamentosProximosScreen> createState() =>
      _MedicamentosProximosScreenState();
}

class _MedicamentosProximosScreenState
    extends State<MedicamentosProximosScreen> {
  final FirestoreService _fs = FirestoreService();
  Timer? _timer;
  bool _alarmaAbierta = false;

  /// Registros de hoy para pintar el estado de cada dosis. Se crea una vez por
  /// paciente para no volver a suscribirse en cada rebuild.
  Stream<List<RegistroToma>>? _registrosHoy;
  String? _pacienteIdRegistros;

  /// 0 = "Horario" (pestaña inicial, la función principal), 1 = "Historial".
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_alarmaAbierta) _revisarTomas();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisarTomas();
      _quizasPedirPermisoPantallaCompleta();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = _pacienteId;
    if (id == null) return;
    if (id == _pacienteIdRegistros) return;
    _pacienteIdRegistros = id;
    _registrosHoy = _fs.streamRegistrosDePacienteHoy(id);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? get _pacienteId => context.read<AppState>().pacienteVinculado?.id;

  /// Detecta horarios de hoy que estén a punto de vencer (ya pasaron o en los
  /// próximos 2 minutos) y sin confirmación registrada, y abre la alarma.
  Future<void> _revisarTomas() async {
    final pacienteId = _pacienteId;
    if (pacienteId == null || !mounted || _alarmaAbierta) return;
    // BootstrapScreen también puede abrir la alarma desde una notificación;
    // AppState es la fuente compartida para no mostrar dos al mismo tiempo.
    if (context.read<AppState>().alarmaAbierta) return;

    final tratamientos = await _fs
        .streamTratamientosDePaciente(pacienteId)
        .first;
    final ahora = DateTime.now();

    Tratamiento? candidato;
    TimeOfDay? horarioCandidato;
    for (final t in tratamientos) {
      // Un tratamiento terminado no debe abrir la alarma automáticamente.
      if (!VigenciaTratamiento.estaVigente(t, ahora)) continue;
      for (final hRaw in t.horarios) {
        // Un horario con dias: [1,3,5] no debe dispararse un martes.
        // `DateTime.weekday` ya es ISO (1=lunes … 7=domingo), igual que
        // `HorarioDia.dias`.
        if (!hRaw.dias.contains(ahora.weekday)) continue;
        final hh = hRaw.hora.split(':');
        if (hh.length != 2) continue;
        final fechaToma = DateTime(
          ahora.year,
          ahora.month,
          ahora.day,
          int.parse(hh[0]),
          int.parse(hh[1]),
        );
        final diff = fechaToma.difference(ahora);

        // Toma "due": ya pasó su hora y aún no fue confirmada, o está por
        // vencer dentro de 2 minutos.
        if (diff.inSeconds <= 120 && diff.inSeconds >= -300) {
          if (!await _yaConfirmada(pacienteId, t.id, fechaToma)) {
            candidato = t;
            horarioCandidato = TimeOfDay(
              hour: int.parse(hh[0]),
              minute: int.parse(hh[1]),
            );
            break;
          }
        }
      }
      if (candidato != null) break;
    }

    if (candidato != null &&
        mounted &&
        !context.read<AppState>().alarmaAbierta) {
      _abrirAlarma(candidato, horarioCandidato!, pacienteId);
    }
  }

  /// Pide una sola vez el permiso de pantalla completa (Android 14+).
  ///
  /// En Android anterior el permiso no existe y no se muestra nada. Si el
  /// paciente lo deniega, la alarma sigue llegando como notificación normal y
  /// no se le vuelve a interrumpir en cada apertura.
  Future<void> _quizasPedirPermisoPantallaCompleta() async {
    // Deja que _revisarTomas tenga oportunidad de abrir una alarma primero:
    // no queremos tapar la pantalla de alarma con este diálogo.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || _alarmaAbierta || context.read<AppState>().alarmaAbierta) {
      return;
    }

    final notif = NotificacionesService();
    final sdk = await notif.androidSdkInt();
    if (sdk == null || sdk < 34) return;
    if (await LocalStore.getPantallaCompletaPreguntada()) return;

    final puede = await notif.puedeUsarPantallaCompleta();
    if (puede != false ||
        !mounted ||
        _alarmaAbierta ||
        context.read<AppState>().alarmaAbierta) {
      return;
    }

    // Se marca antes de mostrar: si la app muere mientras el paciente está en
    // Ajustes, el aviso no vuelve a aparecer.
    await LocalStore.marcarPantallaCompletaPreguntada();
    if (!mounted || _alarmaAbierta || context.read<AppState>().alarmaAbierta) {
      return;
    }

    final permitir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alarma a pantalla completa'),
        content: const Text(
          'Para que la alarma de tus medicamentos aparezca en pantalla completa, '
          'incluso con el teléfono bloqueado, Android necesita un permiso '
          'adicional.\n\n'
          'Si no lo activas, la alarma seguirá llegando como notificación normal.',
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
    if (permitir != true || !mounted) return;

    try {
      final concedido = await notif.solicitarPermisoPantallaCompleta();
      if (!mounted || concedido != false) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El permiso no se activó. La alarma seguirá llegando como '
            'notificación normal.',
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo solicitar el permiso de pantalla completa: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el permiso de pantalla completa.'),
        ),
      );
    }
  }

  /// Abre la pantalla de alarma y mantiene el aviso en [AppState].
  ///
  /// El aviso importa: mientras una alarma está en pantalla la reconciliación
  /// de tomas olvidadas se detiene. Sin él, un paciente que está mirando la
  /// alarma de las 08:00 sin haber tocado "YA" todavía vería cómo, al llegar la
  /// alarma de las 20:00, su toma de las 08:00 se marcaba como olvidada — y si
  /// luego pulsara "YA" quedaría con dos registros para la misma ranura.
  void _abrirAlarma(
    Tratamiento tratamiento,
    TimeOfDay hora,
    String pacienteId,
  ) {
    final appState = context.read<AppState>();
    _alarmaAbierta = true;
    appState.setAlarmaAbierta(true);
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AlarmaScreen(
              tratamiento: tratamiento,
              horaProgramada: hora,
              pacienteId: pacienteId,
            ),
          ),
        )
        .then((_) {
          _alarmaAbierta = false;
          appState.setAlarmaAbierta(false);
        });
  }

  /// ¿Esta toma concreta (esta ranura) ya está resuelta?
  ///
  /// La coincidencia es EXACTA por ranura: mismo tratamiento y misma
  /// `horaProgramada`. Antes solo miraba si el tratamiento tenía cualquier
  /// registro terminal del día, lo que estaba bien mientras cada medicamento
  /// tenía una sola toma diaria, pero con dos tomas (08:00 y 20:00) confirmar
  /// la de las 08:00 hacía que la alarma de las 20:00 no abriera nunca.
  ///
  /// Solo cuentan los estados terminales: una toma pospuesta se reagendó, así que
  /// sigue sin resolverse (ver `EstadoToma.esTerminal`).
  Future<bool> _yaConfirmada(
    String pacienteId,
    String tratamientoId,
    DateTime fecha,
  ) async {
    final registros = await _fs
        .streamTomasPendientesHoy(pacienteId, tratamientoId)
        .first;
    return RegistrosToma.finalDeRanura(
          registros,
          tratamientoId: tratamientoId,
          horaProgramada: fecha,
        ) !=
        null;
  }

  @override
  Widget build(BuildContext context) {
    final pacienteId = _pacienteId;
    if (pacienteId == null) {
      return const Scaffold(body: Center(child: Text('Sin paciente')));
    }

    return GestureDetector(
      onLongPress: _mostrarDialogoSalida,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(_pestana == 0 ? 'Tus medicamentos' : 'Historial'),
            automaticallyImplyLeading: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _mostrarDialogoSalida,
                  icon: const Icon(Icons.logout, size: 22),
                  label: const Text('Salir'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.onGreen,
                    minimumSize: const Size(88, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // IndexedStack mantiene vivas las dos pestañas: al volver a "Horario"
          // la lista no se vuelve a cargar (ni aparece un spinner) y el título
          // del AppBar va en seguimiento de la pestaña activa.
          body: IndexedStack(
            index: _pestana,
            children: [
              _listaHorario(pacienteId),
              _PestanaHistorial(pacienteId: pacienteId),
            ],
          ),
          bottomNavigationBar: _barraDePestanas,
        ),
      ),
    );
  }

  /// Barra inferior: solo dos destinos, con íconos y letras grandes porque este
  /// rol es para personas con deficiencia cognitiva leve a moderada: el área
  /// táctil grande y la etiqueta corta ("Horario", "Historial") son la parte
  /// que hay que poder leer y acertar rápido. La pestaña activa se marca con
  /// el verde de acento y con la letra más grande, no solo con el color.
  Widget get _barraDePestanas => BottomNavigationBar(
    currentIndex: _pestana,
    onTap: (i) => setState(() => _pestana = i),
    type: BottomNavigationBarType.fixed,
    selectedItemColor: AppColors.accent,
    unselectedItemColor: AppColors.textSecondary,
    iconSize: 32,
    selectedFontSize: 17,
    unselectedFontSize: 15,
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Horario'),
      BottomNavigationBarItem(icon: Icon(Icons.medication), label: 'Historial'),
    ],
  );

  /// Lista de medicamentos que hoy tienen toma.
  ///
  /// Es la vista que ya existía, sin cambios en su lógica.
  Widget _listaHorario(String pacienteId) {
    return StreamBuilder<List<Tratamiento>>(
      stream: _fs.streamTratamientosDePaciente(pacienteId),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Text(
              'Error al cargar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ahora = DateTime.now();
        final todos = snap.data ?? const <Tratamiento>[];
        // Solo se listan los medicamentos que hoy tienen algún horario
        // aplicable. Si hoy no toca, no hay nada que tomar.
        final tratamientos = todos
            .where(
              (t) => OmitidasService.ranurasDelDia([t], ahora).isNotEmpty,
            )
            .toList();
        if (tratamientos.isEmpty) {
          return _Empty(hayTratamientos: todos.isNotEmpty);
        }
        return StreamBuilder<List<RegistroToma>>(
          stream: _registrosHoy,
          builder: (context, regSnap) {
            if (regSnap.connectionState == ConnectionState.waiting &&
                !regSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Si la lectura de hoy falla, se sigue mostrando el horario. La
            // pantalla de alarma vuelve a comprobar la ranura antes de ofrecer
            // "YA", así que no se puede confirmar dos veces por esto.
            final registros = regSnap.data ?? const <RegistroToma>[];
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tratamientos.length,
              itemBuilder: (context, i) {
                final t = tratamientos[i];
                return _CardMedicamento(
                  key: ValueKey(t.id),
                  tratamiento: t,
                  registros: registros,
                  onAbrir: (hora) => _abrirAlarma(t, hora, pacienteId),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Salida del modo paciente: botón visible del AppBar y toque largo, ambos
  /// con la misma confirmación. Queda bloqueado el gesto/flecha de atrás
  /// (PopScope). No cierra la sesión anónima: conserva el UID para poder
  /// reingresar sin código desde la selección de rol. El documento en Firestore
  /// no se modifica; solo el cuidador puede desvincular.
  Future<void> _mostrarDialogoSalida() async {
    final appState = context.read<AppState>();
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Seguro que quieres salir?'),
        content: const Text('Podrás volver a entrar sin escribir el código.'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Salir'),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              minimumSize: const Size(140, 48),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (salir == true && mounted) {
      await appState.salirDelModoPaciente();
    }
  }

}

class _CardMedicamento extends StatelessWidget {
  final Tratamiento tratamiento;
  final List<RegistroToma> registros;
  final ValueChanged<TimeOfDay> onAbrir;

  const _CardMedicamento({
    super.key,
    required this.tratamiento,
    required this.registros,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final slots = OmitidasService.ranurasDelDia([tratamiento], ahora)
      ..sort((a, b) => a.horaProgramada.compareTo(b.horaProgramada));
    final porRanura = <String, RegistroToma>{
      for (final r in RegistrosToma.deduplicarPorRanura(registros))
        RegistrosToma.clave(r): r,
    };

    TimeOfDay? proximaPendiente;
    final filas = <Widget>[];
    for (final slot in slots) {
      final registro =
          porRanura[RegistrosToma.claveDeRanura(
            tratamiento.id,
            slot.horaProgramada,
          )];
      if (!(registro?.estado.esTerminal ?? false) &&
          proximaPendiente == null) {
        proximaPendiente = TimeOfDay(
          hour: slot.horaProgramada.hour,
          minute: slot.horaProgramada.minute,
        );
      }
      filas.add(_FilaDosis(slot: slot, registro: registro));
    }

    final bytesFoto =
        (tratamiento.fotoBase64 != null && tratamiento.fotoBase64!.isNotEmpty)
        ? ImagenService.decodificar(tratamiento.fotoBase64!)
        : null;
    final tieneFoto = bytesFoto != null;
    final textoVigencia =
        VigenciaTratamiento.textoParaPaciente(tratamiento, ahora) ??
        ((tratamiento.duracion != null && tratamiento.duracion!.isNotEmpty)
            ? tratamiento.duracion
            : null);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: proximaPendiente == null
            ? null
            : () => onAbrir(proximaPendiente!),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary,
                foregroundImage: tieneFoto ? MemoryImage(bytesFoto) : null,
                child: tieneFoto
                    ? null
                    : const Icon(
                        Icons.medication,
                        size: 32,
                        color: AppColors.accent,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tratamiento.nombreMedicamento,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...filas,
                    if (textoVigencia != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        textoVigencia,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                proximaPendiente == null
                    ? Icons.check_circle
                    : Icons.chevron_right,
                color: proximaPendiente == null
                    ? AppColors.accent
                    : AppColors.textSecondary,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una dosis de hoy dentro de la tarjeta de un medicamento.
class _FilaDosis extends StatelessWidget {
  final RanuraToma slot;
  final RegistroToma? registro;

  const _FilaDosis({required this.slot, required this.registro});

  @override
  Widget build(BuildContext context) {
    final (etiqueta, color, icono) = switch (registro?.estado) {
      EstadoToma.tomada => ('Tomada', AppColors.accent, Icons.check_circle),
      EstadoToma.tardia => (
        'Tomada con retraso',
        AppColors.amber,
        Icons.timer_outlined,
      ),
      EstadoToma.olvidada => ('No se tomó', AppColors.error, Icons.cancel),
      EstadoToma.pospuesta => (
        'Recordada',
        AppColors.warning,
        Icons.schedule,
      ),
      _ => ('Pendiente', AppColors.textSecondary, Icons.schedule),
    };
    final h = slot.horaProgramada.hour.toString().padLeft(2, '0');
    final m = slot.horaProgramada.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            '$h:$m',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.onGreen,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 16, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pestaña "Historial": los últimos registros de toma, del más reciente al
/// más antiguo.
///
/// A propósito sin gráficos, porcentajes ni contadores: solo qué medicamento,
/// cómo salió la toma y a qué hora.
class _PestanaHistorial extends StatefulWidget {
  final String pacienteId;

  /// Suficiente para revisar qué se tomó en los últimos días sin convertir la
  /// pantalla en un listado infinito.
  static const int limite = 20;

  const _PestanaHistorial({required this.pacienteId});

  @override
  State<_PestanaHistorial> createState() => _PestanaHistorialState();
}

class _PestanaHistorialState extends State<_PestanaHistorial> {
  final FirestoreService _fs = FirestoreService();

  /// `RegistroToma` no guarda el nombre del medicamento, solo su
  /// `tratamientoId`, así que se resuelve contra los tratamientos del paciente.
  /// Se mantiene por stream para que un renombre se refleje sin reabrir la
  /// pantalla.
  Map<String, String> _nombres = {};
  StreamSubscription<List<Tratamiento>>? _subNombres;

  @override
  void initState() {
    super.initState();
    _subNombres = _fs.streamTratamientosDePaciente(widget.pacienteId).listen(
      (tratamientos) {
        if (!mounted) return;
        setState(() {
          _nombres = {for (final t in tratamientos) t.id: t.nombreMedicamento};
        });
      },
      // Si no se pueden leer, cada fila cae al texto genérico.
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _subNombres?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RegistroToma>>(
      stream: _fs.streamRegistrosDePaciente(
        widget.pacienteId,
        limite: _PestanaHistorial.limite,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              snap.error.toString(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final registros = snap.data ?? const <RegistroToma>[];
        if (registros.isEmpty) {
          return const Center(
            child: Text(
              'Todavía no hay tomas registradas.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: registros.length,
          itemBuilder: (context, i) {
            final r = registros[i];
            return _FilaHistorial(
              // El registro sobrevive al borrado del tratamiento, así que el
              // nombre puede no estar: en ese caso se muestra genérico.
              nombreMedicamento: _nombres[r.tratamientoId] ?? 'Medicamento',
              registro: r,
            );
          },
        );
      },
    );
  }
}

/// Una fila del historial: ícono grande, medicamento y hora. Nada más.
class _FilaHistorial extends StatelessWidget {
  final String nombreMedicamento;
  final RegistroToma registro;
  const _FilaHistorial({
    required this.nombreMedicamento,
    required this.registro,
  });

  @override
  Widget build(BuildContext context) {
    // Cada estado tiene su ícono y su palabra: un ícono neutro sin texto dejaría
    // al paciente sin saber si la toma se tomó tarde o nunca se tomó.
    final (icono, color, etiqueta) = switch (registro.estado) {
      EstadoToma.tomada => (Icons.check_circle, AppColors.accent, ''),
      EstadoToma.tardia => (Icons.timer_outlined, AppColors.amber, 'Tarde'),
      EstadoToma.pospuesta => (Icons.schedule, AppColors.warning, 'Recordada'),
      EstadoToma.olvidada => (Icons.cancel, AppColors.error, 'No se tomó'),
      _ => (Icons.remove_circle_outline, AppColors.textSecondary, ''),
    };
    final h = registro.horaProgramada.hour.toString().padLeft(2, '0');
    final m = registro.horaProgramada.minute.toString().padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icono, size: 44, color: color),
        title: Text(
          nombreMedicamento,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            '${_etiquetaDia(registro.horaProgramada, DateTime.now())} · $h:$m',
            if (etiqueta.isNotEmpty) etiqueta,
          ].join(' · '),
          style: const TextStyle(fontSize: 24, color: AppColors.onGreen),
        ),
      ),
    );
  }

  /// "Hoy", "Ayer" o el nombre corto del día: "Lun", "Mar", "Mié", "Jue",
  /// "Vie", "Sáb", "Dom".
  ///
  /// La diferencia de días se calcula con fechas en UTC a propósito: entre dos
  /// medianoche locales, un cambio de horario de verano puede dar 23 o 25
  /// horas, y `inDays` sobre esa duración redondearía mal (un "Ayer" rotulado
  /// como "Hoy").
  static String _etiquetaDia(DateTime fecha, DateTime ahora) {
    const nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final dia = DateTime.utc(fecha.year, fecha.month, fecha.day);
    final hoy = DateTime.utc(ahora.year, ahora.month, ahora.day);
    final dias = hoy.difference(dia).inDays;

    if (dias == 0) return 'Hoy';
    if (dias == 1) return 'Ayer';
    return nombres[dia.weekday - 1];
  }
}

class _Empty extends StatelessWidget {
  /// `true` cuando el paciente sí tiene tratamientos pero hoy ninguno aplica
  /// (todos filtrados por día), frente a `false` cuando no tiene ninguno.
  final bool hayTratamientos;
  const _Empty({required this.hayTratamientos});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medication, size: 80, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              hayTratamientos
                  ? 'Hoy no tienes tomas'
                  : 'Todavía no tienes medicamentos',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onGreen, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              hayTratamientos
                  ? 'Ningún medicamento tiene horario para hoy.'
                  : 'Tu cuidador los va a agregar.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
