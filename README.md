# MediPlan / Pastillero Familiar

App móvil multiplataforma (Flutter) de control de medicamentos para personas con
deficiencia cognitiva leve a moderada. Conecta a un **cuidador/doctor** con uno o
varios **pacientes** con dos experiencias de interfaz completamente distintas.
Backend **100% cliente + reglas de Firestore**: no usa Cloud Functions, no usa
FCM, no usa Storage ni plan Blaze.

## Roles

- **Doctor / Cuidador** — Se autentica con Firebase Auth (correo/contraseña o
  Google). Crea pacientes, genera códigos de vinculación, configura
  tratamientos (nombre, foto, dosis, horarios, frecuencia) y ve el estado de
  cumplimiento en tiempo real (dashboard con actividad reciente + notificación
  local cuando la app está abierta).
- **Paciente** — Sin login. Ingresa un código para unirse, ve "Medicamentos
  próximos" con íconos y navegación mínima, y recibe una pantalla de alarma con
  foto real, brillo automático, vibración y botones **YA** / **Recordar**.

## Estructura

```
lib/
  main.dart                  → init Firebase + notificaciones + arranque
  app.dart                   → MaterialApp + router por rol (HomeRouter)
  firebase_options.dart      → config de Firebase (⬅️ correr flutterfire configure)
  models/                    → Usuario, Paciente, Tratamiento, RegistroToma
  services/
    auth_service.dart        → login/registro cuidador, Google Sign-In
    firestore_service.dart   → acceso a Firestore (pacientes, tratamientos, registros)
    vinculacion_service.dart → generación/validación de código + sesión anónima
    notificaciones_service.dart → alarmas locales + notificación local al cuidador
    sensores_service.dart    → vibración + luz ambiental + brillo
    imagen_service.dart      → foto del medicamento comprimida a base64 (sin Storage)
    local_store.dart         → persistencia local del vínculo dispositivo-paciente
  providers/app_state.dart   → estado global por rol
  screens/
    seleccion_rol_screen.dart
    doctor/   login, dashboard, nuevo_paciente, detalle_paciente, editar_tratamiento
    paciente/ codigo_unirse, medicamentos_proximos, alarma
firestore.rules              → reglas de seguridad de Firestore (toda la lógica)
```

## Modelo de datos (Firestore)

Colecciones:

- `usuarios/{uid}` — cuidador/doctor: `nombre`, `correo`.
- `pacientes/{id}` — `nombre`, `cuidadorId`, `codigoVinculacion`,
  `dispositivoVinculadoId` (UID de la sesión anónima del paciente).
- `tratamientos/{id}` — `pacienteId`, `nombreMedicamento`, `fotoBase64` (foto
  codificada en base64 dentro del documento, ~200-300 KB para cumplir el límite
  de 1 MB de Firestore), `dosis`, `horarios[]` (HH:mm), `frecuencia`.
- `registrosToma/{id}` — `tratamientoId`, `pacienteId`, `horaProgramada`,
  `horaConfirmacion` (nullable), `estado` (`pendiente|tomó|tardó|olvidó|pospuesta`).

### Código de vinculación

Formato `MEDI-XXXXXX` con un alfabeto sin caracteres ambiguos (se omiten `0/O`,
`1/I`, etc.) para facilitar la copia manual. El paciente se autentica de forma
**anónima** (Firebase Auth) y su UID se guarda como `dispositivoVinculadoId`, lo
que hace el vínculo persistir entre reinicios de forma segura.

La vinculación es **100% desde el cliente**: el paciente busca su documento por
código y escribe su propio UID como `dispositivoVinculadoId`. Las reglas de
Firestore garantizan que solo pueda asociarse si el documento estaba libre y sin
alterar el código ni el cuidador (ver `firestore.rules` en la raíz).

## Setup de Firebase

### 1. Crear el proyecto y habilitar servicios

1. Consola Firebase → *Agregar proyecto* (ej. `mediplan-proyecto`).
2. Habilitar **Authentication** (métodos: correo/contraseña, Google, *Anonymous*).
3. Habilitar **Cloud Firestore**. *No* se usa Cloud Functions, Firebase Storage
   ni Cloud Messaging (todo corre desde el cliente + reglas de Firestore), por
   lo que no hace falta el plan Blaze.

### 2. Configurar la app Flutter (Android + iOS)

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Esto rellena `lib/firebase_options.dart` con tus claves y añade
`google-services.json` (Android) y `GoogleService-Info.plist` (iOS). Hasta que lo
corras, la app **no** podrá conectarse a ningún servicio.

> Nota: `lib/firebase_options.dart` es un placeholder con `TU_API_KEY_...` como
> valores; `flutterfire configure` lo sobrescribe.

### 3. Desplegar las reglas de Firestore

```bash
# Reglas de Firestore (toda la lógica de acceso vive aquí)
firebase deploy --only firestore:rules
```

> No hay Cloud Functions ni Storage que desplegar: la vinculación por código y
> las alertas al cuidador corren 100% desde el cliente contra Firestore.

## Notificaciones al cuidador

Las alertas del cuidador **no usan FCM/Cloud Functions**: el dashboard escucha en
tiempo real la colección `registrosToma` de sus pacientes y refleja los cambios
de estado al instante. Además muestra una **notificación local** del teléfono
cuando llega una confirmación.

- Funciona con la app del cuidador en **primer plano o en segundo plano**
  (pausada).
- **No** funciona si la app está **cerrada por completo**: para eso hace falta
  un servidor/FCM, que no se usa por no requerir plan Blaze.

## Prueba del flujo completo

Requisito previo: dos dispositivos/emuladores (uno para cada rol) o alternar
entre la app y la consola de Firestore.

1. **Crear cuidador**: en la app, *Doctor → Registrate* (correo/contraseña).
2. **Crear paciente**: en el dashboard, botón *Nuevo paciente* → genera el
   código `MEDI-XXXXXX`. Compartilo.
3. **Vincular paciente**: en el otro dispositivo, *Paciente → Código para
   unirse* → ingresá el código. (Escritura directa a Firestore, validada por las
   reglas; sin Cloud Functions.)
4. **Configurar tratamiento**: desde el dashboard, abrí el paciente → *Nuevo
   medicamento* → nombre, foto real, dosis, horario(s) y frecuencia. Guardar
   programa las alarmas locales diarias.
5. **Simular la hora de toma**: el paciente ve el medicamento en "Medicamentos
   próximos". Cuando llega el horario (o al tocar el item), se abre la pantalla
   de alarma: foto, brillo al máximo, vibración.
6. **Confirmar**: botón *YA* → registra la toma en Firestore; el dashboard del
   cuidador la refleja en tiempo real y dispara una notificación local.
7. **Ver estado**: en el dashboard del cuidador, el paciente muestra las tomas
   marcadas como *Tomadas/Tardías/Olvidadas* en tiempo real.

Para probar sin esperar la hora: configurá un tratamiento con un horario cercano
a la hora actual, o tocá el item del medicamento para abrir la alarma
directamente.

## Verificación

```bash
flutter pub get
flutter analyze      # sin issues
flutter test         # smoke test básico
```

> El build de Android (`flutter build apk`) requiere tener el NDK instalado en
> el Android SDK local (`sdkmanager "ndk;28.x"`); es un requisito de entorno, no
> de este código.
