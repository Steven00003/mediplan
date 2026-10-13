import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../providers/app_state.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../theme/app_colors.dart';
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

  /// 0 = "Horario" (pestaña inicial, la función principal), 1 = "Historial".
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_alarmaAbierta) _revisarTomas();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarTomas());
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
    if (pacienteId == null || !mounted) return;

    final tratamientos =
        await _fs.streamTratamientosDePaciente(pacienteId).first;
    final ahora = DateTime.now();

    Tratamiento? candidato;
    TimeOfDay? horarioCandidato;
    for (final t in tratamientos) {
      for (final hRaw in t.horarios) {
        // Un horario con dias: [1,3,5] no debe dispararse un martes.
        // `DateTime.weekday` ya es ISO (1=lunes … 7=domingo), igual que
        // `HorarioDia.dias`.
        if (!hRaw.dias.contains(ahora.weekday)) continue;
        final hh = hRaw.hora.split(':');
        if (hh.length != 2) continue;
        final fechaToma = DateTime(ahora.year, ahora.month, ahora.day,
            int.parse(hh[0]), int.parse(hh[1]));
        final diff = fechaToma.difference(ahora);

        // Toma "due": ya pasó su hora y aún no fue confirmada, o está por
        // vencer dentro de 2 minutos.
        if (diff.inSeconds <= 120 && diff.inSeconds >= -300) {
          if (!await _yaConfirmada(pacienteId, t.id, fechaToma)) {
            candidato = t;
            horarioCandidato = TimeOfDay(
                hour: int.parse(hh[0]), minute: int.parse(hh[1]));
            break;
          }
        }
      }
      if (candidato != null) break;
    }

    if (candidato != null && mounted) {
      _abrirAlarma(candidato, horarioCandidato!, pacienteId);
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
      Tratamiento tratamiento, TimeOfDay hora, String pacienteId) {
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
      String pacienteId, String tratamientoId, DateTime fecha) async {
    final registros = await _fs
        .streamTomasPendientesHoy(pacienteId, tratamientoId)
        .first;
    for (final r in registros) {
      if (!_mismaRanura(r.horaProgramada, fecha)) continue;
      if (r.estado.esTerminal) return true;
    }
    return false;
  }

  /// Dos instantes son la misma ranura si coinciden al minuto.
  ///
  /// `horaProgramada` se guarda como `Timestamp` (precisión de milisegundos) y
  /// se construye desde una hora `HH:mm`, así que a nivel de minuto es exacta y
  /// comparar más fino solo añadiría ruido.
  static bool _mismaRanura(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

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
          ),
          // IndexedStack mantiene vivas las dos pestañas: al volver a "Horario"
          // la lista no se vuelve a cargar (ni aparece un spinner) y el título
          // del AppBar va en seguimiento de la pestaña activa.
          body: IndexedStack(
            index: _pestana,
            children: [
              _buildHorario(pacienteId),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: 'Horario',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.medication),
            label: 'Historial',
          ),
        ],
      );

  /// Contenido de la pestaña "Horario": los medicamentos que hoy tienen toma.
  ///
  /// Es la vista que ya existía, sin cambios en su lógica.
  Widget _buildHorario(String pacienteId) {
    return StreamBuilder<List<Tratamiento>>(
      stream: _fs.streamTratamientosDePaciente(pacienteId),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Text('Error al cargar',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final ahora = DateTime.now();
        final todos = snap.data ?? const <Tratamiento>[];
        // Solo se listan los medicamentos que hoy tienen algún horario
        // aplicable: si hoy no toca, no hay nada que tomar y la tarjeta
        // solo ocuparía lugar con un "Próxima: —". El predicado es el
        // propio _proximaToma, así que lista y tarjeta no pueden
        // discrepar.
        final tratamientos = todos
            .where((t) => _proximaToma(t, ahora) != null)
            .toList();
        if (tratamientos.isEmpty) {
          return _Empty(hayTratamientos: todos.isNotEmpty);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tratamientos.length,
          itemBuilder: (context, i) {
            final t = tratamientos[i];
            final proxima = _proximaToma(t, ahora);
            return _CardMedicamento(
              tratamiento: t,
              proxima: proxima,
              onTap: () {
                if (proxima != null) {
                  _abrirAlarma(t, proxima, pacienteId);
                }
              },
            );
          },
        );
      },
    );
  }

  /// Salida oculta: solo toque largo con confirmación. Queda bloqueado el
  /// gesto/flecha de atrás (PopScope). Solo limpia el estado local y cierra la
  /// sesión anónima; el documento en Firestore no se modifica (las reglas no lo
  /// permiten para el paciente), así que el cuidador debe liberar el código
  /// para que se pueda volver a vincular.
  Future<void> _mostrarDialogoSalida() async {
    final appState = context.read<AppState>();
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del modo paciente'),
        content: const Text(
          'Esto desvincula este teléfono. El cuidador tendrá que liberar el '
          'código para volver a vincularlo.',
        ),
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
      await appState.desvincularPaciente();
    }
  }

  TimeOfDay? _proximaToma(Tratamiento t, DateTime ahora) {
    TimeOfDay? proxima;
    for (final hRaw in t.horarios) {
      // Solo cuenta como "próxima" la hora de un día en que el horario aplica;
      // si hoy no toca, el medicamento no muestra hora ni se puede abrir.
      if (!hRaw.dias.contains(ahora.weekday)) continue;
      final hh = hRaw.hora.split(':');
      if (hh.length != 2) continue;
      final hora = TimeOfDay(
          hour: int.parse(hh[0]), minute: int.parse(hh[1]));
      if (proxima == null) {
        proxima = hora;
      } else {
        final actual = hora.hour * 60 + hora.minute;
        final mejor = proxima.hour * 60 + proxima.minute;
        if (actual < mejor) proxima = hora;
      }
    }
    return proxima;
  }
}

class _CardMedicamento extends StatelessWidget {
  final Tratamiento tratamiento;
  final TimeOfDay? proxima;
  final VoidCallback onTap;
  const _CardMedicamento({
    required this.tratamiento,
    required this.proxima,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bytesFoto =
        (tratamiento.fotoBase64 != null && tratamiento.fotoBase64!.isNotEmpty)
            ? ImagenService.decodificar(tratamiento.fotoBase64!)
            : null;
    final tieneFoto = bytesFoto != null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 30,
          backgroundColor: AppColors.primary,
          foregroundImage: tieneFoto ? MemoryImage(bytesFoto) : null,
          child: tieneFoto
              ? null
              : const Icon(Icons.medication,
                  size: 32, color: AppColors.accent),
        ),
        title: Text(
          tratamiento.nombreMedicamento,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Text([
          if (proxima != null)
            'Próxima: ${_fmt(proxima!)} · ${tratamiento.dosis} dosis'
          else
            'Sin horarios',
          // Opcional: solo aparece si se informó.
          if (tratamiento.duracion != null && tratamiento.duracion!.isNotEmpty)
            tratamiento.duracion!,
        ].join(' · '), style: const TextStyle(fontSize: 16)),
        trailing: const Icon(Icons.chevron_right, size: 32),
        onTap: onTap,
      ),
    );
  }

  String _fmt(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
          _nombres = {
            for (final t in tratamientos) t.id: t.nombreMedicamento,
          };
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
            child: Text(snap.error.toString(),
                style: const TextStyle(color: AppColors.textSecondary)),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final registros = snap.data ?? const <RegistroToma>[];
        if (registros.isEmpty) {
          return const Center(
            child: Text('Todavía no hay tomas registradas.',
                style: TextStyle(color: AppColors.textSecondary)),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
