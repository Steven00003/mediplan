import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/tratamiento.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';

/// Pantalla para crear o editar un tratamiento (medicamento) de un paciente.
///
/// Permite configurar: nombre, foto real, dosis, horarios, frecuencia y duración.
/// Al guardar un tratamiento, cancela las alarmas anteriores de ese
/// tratamiento y programa las nuevas: una por cada día de la semana en que
/// aplica cada horario (que funcionan sin conexión y se repiten cada semana).
class EditarTratamientoScreen extends StatefulWidget {
  final String pacienteId;
  final Tratamiento? tratamiento;
  final bool esNuevo;
  const EditarTratamientoScreen({
    super.key,
    required this.pacienteId,
    this.tratamiento,
    required this.esNuevo,
  });

  @override
  State<EditarTratamientoScreen> createState() =>
      _EditarTratamientoScreenState();
}

class _EditarTratamientoScreenState extends State<EditarTratamientoScreen> {
  final FirestoreService _fs = FirestoreService();
  final NotificacionesService _notif = NotificacionesService();
  final ImagenService _imagen = ImagenService();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _nombreController;
  late final TextEditingController _dosisController;
  late final TextEditingController _duracionController;
  final List<_HorarioForm> _horarios = [];
  String _frecuencia = 'Diaria';
  String? _fotoBase64;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.tratamiento;
    _nombreController = TextEditingController(text: t?.nombreMedicamento ?? '');
    _dosisController = TextEditingController(text: t?.dosis ?? '1');
    _duracionController = TextEditingController(text: t?.duracion ?? '');
    _fotoBase64 = t?.fotoBase64;
    _frecuencia = t?.frecuencia.isNotEmpty == true ? t!.frecuencia : 'Diaria';
    if (t != null) {
      for (final h in t.horarios) {
        // Precarga la hora y los días que ya tenía cada HorarioDia.
        _horarios.add(_HorarioForm(_parseHora(h.hora), h.dias.toSet()));
      }
    }
  }

  TimeOfDay _parseHora(String hora) {
    final p = hora.split(':');
    final hh = int.tryParse(p.isNotEmpty ? p[0] : '');
    final mm = int.tryParse(p.length > 1 ? p[1] : '0');
    if (hh == null || mm == null) return TimeOfDay.now();
    return TimeOfDay(hour: hh, minute: mm);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _dosisController.dispose();
    _duracionController.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    final foto = await _picker.pickImage(source: ImageSource.gallery);
    if (foto == null) return;
    setState(() => _cargando = true);
    try {
      final bytes = await foto.readAsBytes();
      final base64 = await _imagen.fotoABase64(bytes);
      if (mounted) {
        setState(() {
          _fotoBase64 = base64;
          _cargando = false;
        });
      }
      if (base64 == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo procesar la foto. Elige otra.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error foto: $e');
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar la foto: $e')),
        );
      }
    }
  }

  Future<void> _agregarHorario() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (hora != null) {
      // Un horario nuevo arranca con todos los días marcados.
      setState(
        () => _horarios.add(_HorarioForm(hora, {...HorarioDia.todosLosDias})),
      );
      _ordenarHorarios();
    }
  }

  void _ordenarHorarios() {
    _horarios.sort(
      (a, b) => (a.hora.hour * 60 + a.hora.minute).compareTo(
        b.hora.hour * 60 + b.hora.minute,
      ),
    );
  }

  /// Garantiza que cada horario tenga al menos un día marcado. Devuelve true si
  /// tuvo que completar alguno, para poder avisar al cuidador.
  bool _completarDiasFaltantes() {
    var completo = false;
    for (final h in _horarios) {
      if (h.dias.isEmpty) {
        h.dias.addAll(HorarioDia.todosLosDias);
        completo = true;
      }
    }
    return completo;
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    final dosis = _dosisController.text.trim();
    final duracion = _duracionController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa el nombre del medicamento.');
      return;
    }
    if (_horarios.isEmpty) {
      setState(() => _error = 'Agrega al menos un horario.');
      return;
    }
    // Cada horario necesita al menos un día. Si alguno quedó sin marcar, se
    // marcan todos por defecto y se avisa brevemente; nunca se guarda vacío.
    if (_completarDiasFaltantes()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cada horario necesita al menos un día; se marcaron todos.',
          ),
        ),
      );
      setState(() {});
    }
    setState(() {
      _cargando = true;
      _error = null;
    });

    final tratamiento = Tratamiento(
      id: widget.tratamiento?.id ?? '',
      pacienteId: widget.pacienteId,
      nombreMedicamento: nombre,
      fotoBase64: _fotoBase64,
      dosis: dosis.isEmpty ? '1' : dosis,
      // Cada horario conserva sus propios días seleccionados.
      horarios: _horarios
          .map(
            (h) => HorarioDia(
              hora: _fmtHora(h.hora),
              dias: (h.dias.toList()..sort()),
            ),
          )
          .toList(),
      frecuencia: _frecuencia,
      // Vacío se guarda como null, no como ''.
      duracion: duracion.isEmpty ? null : duracion,
    );

    try {
      String id = tratamiento.id;
      if (widget.esNuevo) {
        id = await _fs.crearTratamiento(tratamiento);
      } else {
        await _fs.actualizarTratamiento(tratamiento);
      }

      // Cancela las notificaciones del estado ANTERIOR de este tratamiento
      // (alarma, aviso previo y recordatorio tardío de todas sus
      // combinaciones hora+día) antes de programar las nuevas, para no dejar
      // avisos huérfanos de horarios que ya no existen.
      final horariosAnteriores =
          widget.tratamiento?.horarios ?? const <HorarioDia>[];
      await _notif.cancelarNotificacionesDeTratamiento(
        tratamientoId: id,
        horarios: horariosAnteriores,
      );

      // Programa alarma, aviso previo y recordatorio tardío por cada día de
      // cada horario.
      for (final h in tratamiento.horarios) {
        await _notif.programarNotificacionesDeHorario(
          tratamientoId: id,
          horario: h,
          nombreMedicamento: nombre,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo guardar el tratamiento.';
          _cargando = false;
        });
      }
    }
  }

  String _fmtHora(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Tarjeta de un horario: su hora, los 7 toggles de días (ISO 1=lunes … 7) y
  /// el botón de borrar. Cada horario mantiene su propio set de días.
  Widget _horarioWidget(int index, _HorarioForm horario) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _fmtHora(horario.hora),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.error,
                  tooltip: 'Quitar horario',
                  onPressed: () => setState(() => _horarios.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < _diasSemana.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _DiaToggle(
                      etiqueta: _diasSemana[i],
                      seleccionado: horario.dias.contains(i + 1),
                      onTap: () => setState(() {
                        final dia = i + 1;
                        if (!horario.dias.remove(dia)) horario.dias.add(dia);
                      }),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Opciones de frecuencia. Se guardan tal cual en el campo de texto libre
  /// `frecuencia`, así que agregar una opción no afecta a las ya almacenadas.
  List<DropdownMenuItem<String>> get _frecuenciaItems => [
    const DropdownMenuItem(value: 'Diaria', child: Text('Diaria')),
    const DropdownMenuItem(value: 'Cada 12 h', child: Text('Cada 12 h')),
    const DropdownMenuItem(value: 'Cada 8 h', child: Text('Cada 8 h')),
    const DropdownMenuItem(value: 'Semanal', child: Text('Semanal')),
    const DropdownMenuItem(
      value: 'Solo cuando sea necesario',
      child: Text('Solo cuando sea necesario'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.esNuevo ? 'Nuevo medicamento' : 'Editar medicamento',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto
            Center(child: _fotoWidget()),
            const SizedBox(height: 16),
            // Nombre
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre del medicamento',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Dosis
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dosisController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Dosis',
                      suffixText: 'dosis',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _frecuencia,
                    onChanged: (v) => setState(() => _frecuencia = v!),
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia',
                      border: OutlineInputBorder(),
                    ),
                    items: _frecuenciaItems,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Duración (texto libre opcional)
            TextField(
              controller: _duracionController,
              decoration: const InputDecoration(
                labelText: 'Duración del tratamiento',
                hintText: 'Ej: 7 días, Continuo',
                helperText: 'Opcional',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            const Text(
              'Horarios',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_horarios.isEmpty)
              const Text(
                'Sin horarios agregados.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ..._horarios.asMap().entries.map(
              (e) => _horarioWidget(e.key, e.value),
            ),
            OutlinedButton.icon(
              onPressed: _agregarHorario,
              icon: const Icon(Icons.add_alarm),
              label: const Text('Agregar horario'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _cargando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                ),
                child: _cargando
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onAccent,
                        ),
                      )
                    : Text(
                        widget.esNuevo ? 'Guardar' : 'Guardar cambios',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fotoWidget() {
    Widget contenido;
    if (_cargando) {
      contenido = const Center(child: CircularProgressIndicator());
    } else if (_fotoBase64 != null && _fotoBase64!.isNotEmpty) {
      final bytes = ImagenService.decodificar(_fotoBase64!);
      contenido = bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                bytes,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _IconoFoto(),
              ),
            )
          : const _IconoFoto();
    } else {
      contenido = const _IconoFoto();
    }
    return GestureDetector(
      onTap: _elegirFoto,
      child: Column(
        children: [
          contenido,
          const SizedBox(height: 8),
          const Text(
            'Toca para elegir la foto real',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _IconoFoto extends StatelessWidget {
  const _IconoFoto();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.add_a_photo, size: 56, color: AppColors.accent),
    );
  }
}

/// Etiquetas de los días en orden ISO 8601: índice 0 = lunes … índice 6 =
/// domingo.
const List<String> _diasSemana = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Estado del formulario para un horario: la hora elegida y los días marcados.
class _HorarioForm {
  TimeOfDay hora;
  final Set<int> dias;

  _HorarioForm(this.hora, this.dias);
}

/// Botón de un día de la semana: toggle con el aspecto de la paleta.
class _DiaToggle extends StatelessWidget {
  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onTap;

  const _DiaToggle({
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionado ? AppColors.accent : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Text(
          etiqueta,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: seleccionado ? AppColors.onAccent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
