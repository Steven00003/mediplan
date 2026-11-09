import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Pantalla mínima de la alarma de prueba del diagnóstico.
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
        title: const Text('Prueba de alarma'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.alarm_on, size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text(
              'La alarma abrió la app',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.onGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta pantalla es solo una prueba: no registra ninguna toma.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            _dato('Hora programada', _formatear(widget.horaProgramada)),
            _dato('Hora real de apertura', _formatear(_horaApertura)),
            _dato('Diferencia', '${segundos}s'),
            const SizedBox(height: 12),
            Text(
              textoDiferencia,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: AppColors.onGreen),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            Text(
              valor,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.onGreen,
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
