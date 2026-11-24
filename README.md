# MediPlan

Aplicacion movil (Flutter) de control de medicamentos para personas con
deficiencia cognitiva leve a moderada. Conecta a un cuidador o doctor con uno o
varios pacientes mediante dos experiencias de interfaz distintas.

Backend 100% cliente + reglas de Firestore: no usa Cloud Functions, no usa
Storage ni plan Blaze. La alerta de 5 dias sin tomas usa push FCM HTTP v1
enviado desde el celular del paciente.

## Roles

- **Doctor / Cuidador**: se autentica con Firebase Auth (correo y contrasena o
  Google). Crea pacientes, genera codigos de vinculacion, configura tratamientos
  y ve el cumplimiento en tiempo real.
- **Paciente**: sin login. Se vincula con un codigo, ve sus medicamentos
  proximos, recibe alarmas y confirma cada toma.

## Funciones actuales

- Vinculacion por codigo `MEDI-XXXXXX` con vencimiento de 72 horas.
- Alarmas en una ventana movil de 7 dias, con aviso previo, felicitacion y
  recordatorio tardio.
- Detalle del medicamento y ventana de confirmacion.
- Historial y estadisticas de tomas.
- Alerta al cuidador si un paciente lleva 5 dias sin tomas registradas.
- Perfil publico del doctor (`medicos/{uid}`) y tarjeta "Tu medico" para el
  paciente.
- Tarjeta "Celular del paciente" y pantalla "Comprobar mi celular".
- Asistente de permisos para el paciente.
- Eliminacion de pacientes con borrado completo y limpieza del celular.
- Desvinculacion y reconciliacion de tomas olvidadas.

## Stack

- Flutter 3.47.2 / Dart 3.13.2
- Firebase Auth, Cloud Firestore, Firebase Messaging
- flutter_local_notifications, screen_brightness, image_picker
- Reglas de Firestore en `firestore.rules`

## Configuracion de Firebase

1. Crea o usa el proyecto `mediplan-35953`.
2. Coloca `android/app/google-services.json` y `lib/firebase_options.dart`.
3. Despliega reglas con:

   `firebase deploy --only firestore:rules --project mediplan-35953`

No despliegues reglas ni indices sin avisar que cambia.

## Push FCM

Genera `assets/secrets/fcm_service_account.json` segun
`assets/secrets/README.md`. Si falta, la app sigue funcionando, pero el push de
sincronizacion y la alerta de 5 dias no se envian; las notificaciones locales
siguen activas.

## Compilacion

Compila siempre en debug:

`flutter build apk --debug`

No uses `--release`: la firma release con la clave de depuracion cambia la
firma y rompe el login de Google.

## Tests y analisis

- `flutter analyze`
- `flutter test`
- Para un archivo: `flutter test test/<archivo>.dart`

Ejecuta analyze y test de forma secuencial.

## Matriz de versiones de Android probadas

| Android | Dispositivo | Estado |
|---|---|---|
| 9 | Huawei Y9 Prime | Probado: alarma sonó y abrió la app |
| 11 | Motorola G20 | Probado: alarma funcionó |
| (versión por confirmar) | Samsung Galaxy A36 | Probado: alarma funcionó |

## Limitaciones conocidas

- iOS no esta soportado en esta version: maximo 64 notificaciones locales,
  sin alarma a pantalla completa ni arranque en segundo plano, y FCM requiere
  cuenta de Apple Developer.
- Algunos fabricantes con ahorro agresivo de bateria o canales silenciosos
  (caso Huawei) pueden requerir activar sonido e inicio automatico manualmente.
- La credencial FCM viaja dentro del APK y es extraible.
- Las fotos se guardan como base64 en Firestore; no se usa Storage.

## Documentacion

- `ESQUEMA.md`: modelo de datos y reglas.
- `AGENTS.md`: arquitectura, comandos y estado del proyecto.
