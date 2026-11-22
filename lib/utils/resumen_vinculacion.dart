import '../models/estado_dispositivo.dart';
import 'estado_codigo_vinculacion.dart';
import 'reporte_estado_dispositivo.dart';

/// Resumen de una línea que se muestra siempre en el encabezado de la sección
/// de vinculación, incluso cuando está colapsada.
class ResumenVinculacion {
  final String texto;
  final bool advertencia;

  const ResumenVinculacion({required this.texto, required this.advertencia});
}

ResumenVinculacion resumenVinculacion({
  required bool vinculado,
  required DateTime? expiraCodigo,
  required DateTime ahora,
  required EstadoDispositivo? estadoDispositivo,
}) {
  if (vinculado) {
    final ultima = textoUltimaSincronizacion(
      estadoDispositivo?.ultimaSincronizacion,
      ahora,
    );
    return ResumenVinculacion(
      texto: 'Vinculado · última conexión $ultima',
      advertencia: necesitaAvisoAlarmas(estadoDispositivo, ahora),
    );
  }

  if (estadoDelCodigo(expiraCodigo, ahora) == EstadoCodigoVinculacion.vencido) {
    return const ResumenVinculacion(
      texto: 'Código vencido',
      advertencia: false,
    );
  }

  return const ResumenVinculacion(texto: 'Sin vincular', advertencia: false);
}
