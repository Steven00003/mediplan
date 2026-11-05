import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show PendingNotificationRequest;
import 'package:provider/provider.dart';

import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../providers/app_state.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../services/local_store.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';
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
      debugPrint('No se pudo solicitar el permiso de pantalla completa: $e');
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
      BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Horario'),
      BottomNavigationBarItem(icon: Icon(Icons.medication), label: 'Historial'),
    ],
  );

  /// Contenido de la pestaña "Horario": el botón temporal de diagnóstico y
  /// la lista de medicamentos.
  Widget _buildHorario(String pacienteId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _mostrarDiagnosticoAlarmas,
              icon: const Icon(Icons.alarm),
              label: const Text('Ver alarmas programadas'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _listaHorario(pacienteId)),
      ],
    );
  }

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

  Future<void> _mostrarDiagnosticoAlarmas() {
    return showDialog<void>(
      context: context,
      builder: (_) => const _DialogoDiagnosticoAlarmas(),
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

  TimeOfDay? _proximaToma(Tratamiento t, DateTime ahora) {
    // Fuera de la fecha de inicio/fin el medicamento no está activo en Horario.
    if (!VigenciaTratamiento.estaVigente(t, ahora)) return null;
    TimeOfDay? proxima;
    for (final hRaw in t.horarios) {
      // Solo cuenta como "próxima" la hora de un día en que el horario aplica;
      // si hoy no toca, el medicamento no muestra hora ni se puede abrir.
      if (!hRaw.dias.contains(ahora.weekday)) continue;
      final hh = hRaw.hora.split(':');
      if (hh.length != 2) continue;
      final hora = TimeOfDay(hour: int.parse(hh[0]), minute: int.parse(hh[1]));
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

/// Diálogo temporal de diagnóstico de alarmas.
///
/// Solo consulta: no programa, cancela ni modifica notificaciones.
class _DialogoDiagnosticoAlarmas extends StatefulWidget {
  const _DialogoDiagnosticoAlarmas();

  @override
  State<_DialogoDiagnosticoAlarmas> createState() =>
      _DialogoDiagnosticoAlarmasState();
}

class _DialogoDiagnosticoAlarmasState
    extends State<_DialogoDiagnosticoAlarmas> {
  final NotificacionesService _notif = NotificacionesService();

  bool _cargando = true;
  Object? _error;
  List<PendingNotificationRequest> _pendientes = const [];
  bool? _exactas;
  bool? _pantallaCompleta;
  int? _sdk;
  String _zona = '—';
  String _ahoraLocal = '—';
  String _ahoraZona = '—';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pendientes = await _notif.alarmasProgramadas();
      final exactas = await _notif.puedeProgramarAlarmasExactas();
      final pantallaCompleta = await _notif.puedeUsarPantallaCompleta();
      final sdk = await _notif.androidSdkInt();
      if (!mounted) return;
      setState(() {
        _pendientes = pendientes;
        _exactas = exactas;
        _pantallaCompleta = pantallaCompleta;
        _sdk = sdk;
        _zona = _notif.zonaHoraria;
        _ahoraLocal = DateTime.now().toString();
        _ahoraZona = _notif.ahoraEnZonaHoraria;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _cargando = false;
      });
    }
  }

  String get _textoExactas {
    final sdk = _sdk;
    if (sdk != null && sdk < 31) {
      return 'No aplica (Android 11 o anterior)';
    }
    if (_exactas == null) return 'Desconocido';
    return _exactas! ? 'Concedido' : 'Denegado';
  }

  String get _textoPantallaCompleta {
    final sdk = _sdk;
    if (sdk != null && sdk < 34) {
      return 'No aplica (Android 13 o anterior)';
    }
    if (_pantallaCompleta == null) return 'Desconocido';
    return _pantallaCompleta! ? 'Concedido' : 'Denegado';
  }

  String get _textoSdk {
    final sdk = _sdk;
    if (sdk == null) return 'Desconocido';
    final version = switch (sdk) {
      30 => 'Android 11',
      31 => 'Android 12',
      32 => 'Android 12L',
      33 => 'Android 13',
      34 => 'Android 14',
      35 => 'Android 15',
      36 => 'Android 16',
      _ => 'Android',
    };
    return '$version (SDK $sdk)';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Diagnóstico de alarmas'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: _cargando
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fila('Sistema', _textoSdk),
                      _fila('Alarmas exactas', _textoExactas),
                      _fila('Pantalla completa', _textoPantallaCompleta),
                      _fila('Zona horaria usada', _zona),
                      _fila('Ahora local', _ahoraLocal),
                      _fila('Ahora en esa zona', _ahoraZona),
                      if (_zona.toUpperCase() == 'UTC')
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Aviso: timezone está usando UTC. Las horas HH:mm '
                            'se interpretan como UTC, no como hora local.',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Error consultando el plugin: $_error',
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                      const Divider(height: 24),
                      Text(
                        'Notificaciones pendientes (${_pendientes.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Lista interna de flutter_local_notifications; no '
                        'incluye alarmas de otras apps.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_pendientes.isEmpty)
                        const Text(
                          'No hay ninguna notificación programada por el '
                          'plugin en este momento.',
                          style: TextStyle(color: AppColors.textSecondary),
                        )
                      else
                        for (final p in _pendientes)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID: ${p.id}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Payload: ${p.payload ?? '(sin payload)'}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                if (p.title != null && p.title!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Título: ${p.title}'),
                                ],
                                if (p.body != null && p.body!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Cuerpo: ${p.body}'),
                                ],
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cargando ? null : _cargar,
          child: const Text('Actualizar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              etiqueta,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
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
    final textoVigencia =
        VigenciaTratamiento.textoParaPaciente(tratamiento, DateTime.now()) ??
        ((tratamiento.duracion != null && tratamiento.duracion!.isNotEmpty)
            ? tratamiento.duracion
            : null);
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
              : const Icon(Icons.medication, size: 32, color: AppColors.accent),
        ),
        title: Text(
          tratamiento.nombreMedicamento,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            if (proxima != null)
              'Próxima: ${_fmt(proxima!)} · ${tratamiento.dosis} dosis'
            else
              'Sin horarios',
            // Para tratamientos con fecha se muestra el tiempo restante; para
            // continuos o con inicio desconocido, el texto guardado.
            ?textoVigencia,
          ].join(' · '),
          style: const TextStyle(fontSize: 16),
        ),
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
