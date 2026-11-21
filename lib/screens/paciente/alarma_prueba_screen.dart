import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';

/// Pantalla mínima de la alarma de prueba.
///
/// No lee ni escribe Firestore. Solo compara la hora para la que se programó
/// la notificación con la hora real en que la app se abrió.
class AlarmaPruebaScreen extends StatefulWidget {
  final DateTime horaProgramada;

  const AlarmaPruebaScreen({super.key, required this.horaProgramada});

  @override
  State<AlarmaPruebaScreen> createState() => _AlarmaPruebaScreenState();
}

class _AlarmaPruebaScreenState extends State<AlarmaPruebaScreen> {
  late final DateTime _horaApertura;

  @override
  void initState() {
    super.initState();
    _horaApertura = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final diferencia = _horaApertura.difference(widget.horaProgramada);
    final segundos = diferencia.inSeconds;
    final textoDiferencia = segundos >= 0
        ? 'La app se abrió ${segundos}s después de la hora programada.'
        : 'La app se abrió ${segundos.abs()}s antes de la hora programada.';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Prueba de alarma',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const Icon(
              Icons.alarm_on,
              size: AppSizes.iconXLarge + AppSizes.iconLarge,
              color: AppColors.primaryStrong,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'La alarma abrió la app',
              textAlign: TextAlign.center,
              style: AppType.title.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Esta pantalla es solo una prueba: no registra ninguna toma.',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            _dato('Hora programada', _formatear(widget.horaProgramada)),
            _dato('Hora real de apertura', _formatear(_horaApertura)),
            _dato('Diferencia', '${segundos}s'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              textoDiferencia,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: AppColors.onGreen),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: AppType.body.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                valor,
                textAlign: TextAlign.right,
                style: AppType.body.copyWith(
                  color: AppColors.onGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatear(DateTime fecha) {
    final h = fecha.hour.toString().padLeft(2, '0');
    final m = fecha.minute.toString().padLeft(2, '0');
    final s = fecha.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
