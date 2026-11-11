import 'package:flutter/material.dart';

import '../models/tratamiento.dart';
import '../services/imagen_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/vigencia_tratamiento.dart';

/// Tarjeta de un medicamento en el detalle del paciente.
///
/// Presenta el nombre, la dosis, la vigencia, el tiempo restante y los horarios
/// agrupados como chips por día. No hace lecturas: recibe el [Tratamiento] ya
/// cargado por la pantalla.
class TarjetaMedicamento extends StatelessWidget {
  final Tratamiento tratamiento;
  final DateTime ahora;
  final VoidCallback onTap;
  final VoidCallback onEliminar;

  const TarjetaMedicamento({
    super.key,
    required this.tratamiento,
    required this.ahora,
    required this.onTap,
    required this.onEliminar,
  });

  static const Map<int, String> _diasCortos = {
    1: 'Lun',
    2: 'Mar',
    3: 'Mié',
    4: 'Jue',
    5: 'Vie',
    6: 'Sáb',
    7: 'Dom',
  };

  static const Map<int, String> _diasLargos = {
    1: 'Lunes',
    2: 'Martes',
    3: 'Miércoles',
    4: 'Jueves',
    5: 'Viernes',
    6: 'Sábado',
    7: 'Domingo',
  };

  bool get _vigente => VigenciaTratamiento.estaVigente(tratamiento, ahora);

  String get _tiempoRestante {
    final dias = VigenciaTratamiento.diasRestantes(tratamiento, ahora);
    if (dias == null) return 'Continuo';
    if (dias <= 0) return 'Tratamiento terminado';
    if (dias == 1) return 'Último día';
    return 'Quedan $dias días';
  }

  List<Widget> _chipsPorDia() {
    final porDia = <int, List<String>>{};
    for (final horario in tratamiento.horarios) {
      for (final dia in horario.dias) {
        (porDia[dia] ??= []).add(horario.hora);
      }
    }

    final dias = porDia.keys.toList()..sort();
    return dias.map((dia) {
      final horas = porDia[dia]!..sort();
      final texto = '${_diasCortos[dia] ?? '?'} ${horas.join(' · ')}';
      final etiqueta =
          '${_diasLargos[dia] ?? 'Día'} a las ${horas.join(' y ')}';
      return _ChipHorario(texto: texto, etiqueta: etiqueta);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final nombre = tratamiento.nombreMedicamento;
    final dosis = tratamiento.dosis.isEmpty ? '1' : tratamiento.dosis;
    final foto = tratamiento.fotoBase64;
    final bytes = (foto != null && foto.isNotEmpty)
        ? ImagenService.decodificar(foto)
        : null;
    final chips = _chipsPorDia();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: AppSizes.iconLarge,
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onGreen,
                    foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                    child: bytes == null
                        ? const Icon(Icons.medication, color: AppColors.onGreen)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.title.copyWith(
                            color: AppColors.onGreen,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Dosis: $dosis',
                          style: AppType.body.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: AppColors.error,
                    tooltip: 'Eliminar medicamento',
                    onPressed: onEliminar,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _EtiquetaVigencia(vigente: _vigente),
                  _EtiquetaTiempo(texto: _tiempoRestante),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EtiquetaVigencia extends StatelessWidget {
  final bool vigente;

  const _EtiquetaVigencia({required this.vigente});

  @override
  Widget build(BuildContext context) {
    final color = vigente ? AppColors.primaryStrong : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        vigente ? 'Vigente' : 'Finalizado',
        style: AppType.label.copyWith(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EtiquetaTiempo extends StatelessWidget {
  final String texto;

  const _EtiquetaTiempo({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(
                color: AppColors.onGreen,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipHorario extends StatelessWidget {
  final String texto;
  final String etiqueta;

  const _ChipHorario({required this.texto, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: etiqueta,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          texto,
          style: AppType.label.copyWith(
            color: AppColors.onGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
