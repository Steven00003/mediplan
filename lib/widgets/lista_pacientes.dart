import 'package:flutter/material.dart';

import '../models/paciente.dart';
import '../theme/app_tokens.dart';
import 'tarjeta_paciente.dart';

/// Lista perezosa de pacientes del cuidador.
///
/// El último elemento es [footer], que en el dashboard es la actividad
/// reciente. Así la lista no construye las 200 tarjetas de golpe.
class ListaPacientes extends StatelessWidget {
  final List<Paciente> pacientes;
  final ValueChanged<Paciente> onTap;
  final Widget footer;

  const ListaPacientes({
    super.key,
    required this.pacientes,
    required this.onTap,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: pacientes.length + 1,
      itemBuilder: (context, index) {
        if (index == pacientes.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: footer,
          );
        }

        final paciente = pacientes[index];
        return TarjetaPaciente(
          paciente: paciente,
          onTap: () => onTap(paciente),
        );
      },
    );
  }
}
