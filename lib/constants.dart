/// Constantes globales de MediPlan.
///
/// La landing se abre desde el logo de la pantalla de selección de rol.
/// Cambia esta URL en un solo lugar cuando el hosting esté confirmado.
const String urlLanding = 'https://mediplan-35953.web.app';

/// Versión visible en "Acerca de".
///
/// Se mantiene aquí como constante para no añadir `package_info_plus` solo por
/// mostrarla. Debe actualizarse a mano cuando cambie `version` en `pubspec.yaml`
/// (hoy `1.0.0+1`).
const String appVersion = '1.0.0+1';

/// Vigencia de un código de vinculación recién generado.
///
/// Pasado este tiempo el paciente debe pedir al cuidador que genere uno nuevo.
/// Los vínculos antiguos sin `expiraEn` se siguen tratando como vigentes.
const Duration duracionCodigoVinculacion = Duration(hours: 72);
