# Credenciales de FCM (push paciente → cuidador)

MediPlan envía las notificaciones al cuidador llamando **directamente** a la API
HTTP v1 de FCM desde el dispositivo del paciente, sin Cloud Functions ni
servidor propio. Para autenticar esa llamada hace falta un JSON de cuenta de
servicio en:

```
assets/secrets/fcm_service_account.json
```

## ⚠️ Aviso de seguridad

Este archivo **viaja dentro del APK** y cualquiera puede extraerlo
(`unzip app-release.apk`). Con él se pueden enviar push ilimitados al proyecto
`mediplan-35953` en nombre de la app. Por eso:

- Crea una cuenta de servicio **dedicada** y dale el **rol mínimo**: un rol
  personalizado con solo `cloudmessaging.messages.create` (o, si no, "Firebase
  Cloud Messaging API Admin", `roles/firebasecloudmessaging.admin`).
- No reutilices la cuenta de servicio del Admin SDK.
- Rota la clave cada 30–90 días y actualiza la app.
- El `.gitignore` excluye `assets/secrets/*.json`: no lo commitees.

La única forma de evitar la exposición es no embarcar la credencial (un proxy
tipo Cloud Run que guarde la clave). El envío es "best effort": sin este archivo
la app funciona igual, solo que no hay push.

## Cómo generarlo

1. Google Cloud Console → elige el proyecto `mediplan-35953`.
2. IAM & Admin → Service accounts → *Create service account*.
3. Asígnale solo el permiso de envío de FCM (ver arriba).
4. En la cuenta → Keys → *Add key* → *Create new key* → **JSON**.
5. Guarda el JSON descargado como `assets/secrets/fcm_service_account.json`.
6. `flutter pub get` (el asset ya está declarado en `pubspec.yaml`).

El código que lo usa es `lib/services/push_service.dart`.
