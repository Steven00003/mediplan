import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/registro_toma.dart';
import '../../models/tratamiento.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/errores_amigables.dart';
import '../../utils/etiqueta_toma.dart';
import '../../utils/proxima_toma.dart';
import '../../utils/vigencia_tratamiento.dart';
import '../../utils/ventana_confirmacion.dart';
import '../../widgets/estados.dart';
import 'alarma_screen.dart';

/// Detalle de solo lectura de un medicamento del paciente.
///
/// No confirma ni pospone tomas por sí mismo. Solo muestra una tarjeta
/// destacada "Es hora de tomarla" cuando hay una dosis pendiente dentro de la
/// ventana de confirmación; al pulsarla abre [AlarmaScreen].
class DetalleMedicamentoPacienteScreen extends StatefulWidget {
  final String pacienteId;
  final Tratamiento tratamiento;

  const DetalleMedicamentoPacienteScreen({
    super.key,
    required this.pacienteId,
    required this.tratamiento,
  });

  @override
  State<DetalleMedicamentoPacienteScreen> createState() =>
      _DetalleMedicamentoPacienteScreenState();
}

class _DetalleMedicamentoPacienteScreenState
    extends State<DetalleMedicamentoPacienteScreen> {
  final FirestoreService _fs = FirestoreService();
  final String? _recetadoPor = null;
  Timer? _reloj;
  late final Future<List<RegistroToma>> _historial;

  /// Hora pendiente dentro de la ventana de confirmación, si la hay.
  TimeOfDay? _horaPendiente;

  @override
  void initState() {
    super.initState();
    _historial = _fs.getHistorialDeTratamiento(
      widget.pacienteId,
      widget.tratamiento.id,
    );
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _buscarDosisPendiente();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _buscarDosisPendiente() async {
    final ahora = DateTime.now();
    final t = widget.tratamiento;
    if (!VigenciaTratamiento.estaVigente(t, ahora)) return;

    for (final h in t.horarios) {
      if (!h.dias.contains(ahora.weekday)) continue;
      final partes = h.hora.split(':');
      if (partes.length != 2) continue;
      final hora = int.tryParse(partes[0]);
      final minuto = int.tryParse(partes[1]);
      if (hora == null || minuto == null) continue;
      final fechaToma = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
        hora,
        minuto,
      );
      if (!estaEnVentanaConfirmacion(fechaToma, ahora)) continue;

      final registro = await _fs.getRegistroFinalDeRanura(
        widget.pacienteId,
        t.id,
        fechaToma,
      );
      if (!mounted) return;
      if (registro == null) {
        setState(() {
          _horaPendiente = TimeOfDay(hour: hora, minute: minuto);
        });
        return;
      }
    }
  }

  void _abrirAlarma() {
    final hora = _horaPendiente;
    if (hora == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlarmaScreen(
          tratamiento: widget.tratamiento,
          horaProgramada: hora,
          pacienteId: widget.pacienteId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tratamiento;
    final ahora = DateTime.now();
    final bytesFoto = (t.fotoBase64 != null && t.fotoBase64!.isNotEmpty)
        ? ImagenService.decodificar(t.fotoBase64!)
        : null;
    final tieneFoto = bytesFoto != null;
    final textoRestante = VigenciaTratamiento.textoParaPaciente(t, ahora);
    final recetadoPor = _recetadoPor;
    final proxima = ProximaToma.calcular(
      tratamiento: t,
      ahora: ahora,
      tomaActual: DateTime(1970),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t.nombreMedicamento)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: [
          if (_horaPendiente != null) ...[
            Card(
              color: AppColors.primary,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.alarm, color: AppColors.primaryStrong),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Es hora de tomarla',
                        style: AppType.title.copyWith(color: AppColors.onGreen),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _abrirAlarma,
                      child: const Text('Registrar toma'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Container(
              width: double.infinity,
              height: 220,
              color: AppColors.surface,
              child: tieneFoto
                  ? Image.memory(
                      bytesFoto,
                      fit: BoxFit.cover,
                      cacheWidth: 640,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.medication,
                        size: 80,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : const Icon(
                      Icons.medication,
                      size: 80,
                      color: AppColors.textSecondary,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            t.nombreMedicamento,
            style: AppType.title.copyWith(color: AppColors.onGreen),
          ),
          if (t.dosis.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Dosis: ${t.dosis}',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (t.frecuencia.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Frecuencia: ${t.frecuencia}',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Horarios',
            style: AppType.label.copyWith(color: AppColors.onGreen),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final h in t.horarios)
                Chip(label: Text('${h.hora} (${h.dias.join(',')})')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Próxima toma',
            style: AppType.title.copyWith(color: AppColors.onGreen),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (proxima.cuando == null)
            Text(
              'Esta es tu última toma',
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            )
          else ...[
            Text(
              '${etiquetaDia(proxima.cuando!, ahora: ahora)} · '
              '${horaCorta(proxima.cuando!)}',
              style: AppType.body.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ProximaToma.formatearCuentaRegresiva(
                proxima.cuando!.difference(ahora),
              ),
              style: AppType.label.copyWith(color: AppColors.primaryStrong),
            ),
          ],
          if (textoRestante != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Tiempo restante',
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              textoRestante,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Historial de este medicamento',
            style: AppType.title.copyWith(color: AppColors.onGreen),
          ),
          const SizedBox(height: AppSpacing.xs),
          FutureBuilder<List<RegistroToma>>(
            future: _historial,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const EstadoCargando(texto: 'Cargando historial...');
              }
              if (snap.hasError) {
                return EstadoError(
                  mensaje: mensajeErrorAmigable(
                    snap.error!,
                    contexto: 'Error cargando historial',
                  ),
                  onReintentar: () {},
                );
              }
              final registros = snap.data ?? const <RegistroToma>[];
              if (registros.isEmpty) {
                return const EstadoVacio(
                  icono: Icons.history,
                  titulo: 'Aún no hay tomas registradas',
                  mensaje: 'Cuando confirmes una toma, aparecerá aquí.',
                );
              }
              return Column(
                children: [
                  for (final r in registros)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        children: [
                          Icon(
                            r.estado == EstadoToma.tomada
                                ? Icons.check_circle
                                : r.estado == EstadoToma.tardia
                                ? Icons.timer_outlined
                                : Icons.cancel,
                            color: r.estado == EstadoToma.tomada
                                ? AppColors.primaryStrong
                                : r.estado == EstadoToma.tardia
                                ? AppColors.amber
                                : AppColors.error,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              '${etiquetaProgramada(r, ahora: ahora)} - '
                              '${r.estado.nombre}',
                              style: AppType.body.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          // Espacio reservado para "Recetado por" cuando exista el dato.
          if (recetadoPor != null && recetadoPor.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Recetado por',
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              recetadoPor,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
