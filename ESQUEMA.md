# ESQUEMA.md — Modelo de datos de Firestore

Documento derivado **exclusivamente** del código: `lib/models/*.dart`,
`lib/services/firestore_service.dart` y `firestore.rules`. Si algo no está
mencionado acá, no existe en el modelo.

No hay backend con Cloud Functions ni Firebase Storage. Todo el modelo se lee y
escribe desde el cliente, y la seguridad vive **enteramente** en
`firestore.rules` (proyecto `mediplan-35953`). La única llamada a un servidor
externo es el push FCM HTTP v1 que el dispositivo del paciente envía al cuidador
para la alerta de **5 días sin tomas** (ver [Push FCM](#push-fcm-la-única-salida-externa)).
Ese push no escribe datos: la fuente de verdad sigue siendo Firestore.

## Los dos roles y sus dos UIDs

| Rol | Firebase Auth | Dónde aparece su UID |
|---|---|---|
| Doctor / Cuidador | correo/contraseña o Google, con credenciales | `usuarios/{uid}`, `pacientes.cuidadorId` |
| Paciente | `signInAnonymously()`, **sin credenciales** | `pacientes.dispositivoVinculadoId` |

El paciente no tiene cuenta: su UID anónimo **es** su identidad de dispositivo.
Las reglas comparan ese UID contra `request.auth.uid`.

---

## `usuarios/{uid}`

### ID del documento

= **el UID de Firebase Auth**, no autogenerado.
`auth_service.dart:84-91` usa `.collection('usuarios').doc(user.uid).set(...)`.

Se escribe **solo si el documento no existe** (`auth_service.dart:83`,
`if (!doc.exists)`), así que el perfil nunca se actualiza después de creado.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `uid` | `String` | Nunca null | UID de Auth. **Duplica el ID del documento.** |
| `nombre` | `String` | Nunca null. Puede ser el literal `'Cuidador'` | `nombre ?? user.displayName ?? 'Cuidador'` (`auth_service.dart:89`) |
| `correo` | `String` | Nunca null. **Puede ser `''`** | `user.email ?? ''`; vacío si la cuenta no tiene correo |

`Usuario.fromMap` (`usuario.dart:13-19`) devuelve `''` para cualquier campo
ausente, así que un documento corrupto no rompe la app, devuelve strings vacíos.

### Referencias

Ninguna. Esta colección es la **raíz**: el resto la apunta, no al revés.

`usuarios/{uid}` ← `pacientes.cuidadorId`

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read, create, update | `isAuthenticated() && request.auth.uid == uid` | 25 |
| delete | `if false` — **nadie puede borrar** | 26 |

`isAuthenticated()` (líneas 6-8) solo exige `request.auth != null`.

### Cómo consultar

- La app **nunca lista** `usuarios`: solo hace un `doc(uid).get()` directo en
  `auth_service.dart:79-82`, que cumple la regla porque el uid es el propio.
- Un cuidador **no puede leer** el `usuarios` de otro cuidador. Ni siquiera el
  paciente puede leer nada acá.
- No hace falta ningún filtro `where`: el acceso es por ID directo.

---

## `pacientes/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearPaciente` hace `.add(...)`
(`firestore_service.dart:93`).

`Paciente.toMap()` (`paciente.dart:81-93`) **no** incluye el campo `id`: el `id`
del modelo es solo el ID del documento, y se rellena al leer con
`Paciente.fromMap(snap.id, snap.data())`.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `nombre` | `String` | Nunca null — la regla de `create` lo exige (línea 36) | Nombre del paciente |
| `cuidadorId` | `String` | Nunca null | → `usuarios/{uid}`. En `create` debe ser `request.auth.uid` (línea 34) |
| `codigoVinculacion` | `String` | Nunca null — la regla lo exige (línea 35) | `MEDI-XXXXXX`, el código que el paciente tipea |
| `dispositivoVinculadoId` | `String` | **`''` = libre.** Puede ser `null` en documentos viejos | UID anónimo del Auth del teléfono del paciente |
| `edad` | `int?` | Opcional | Ficha del paciente |
| `condicion` | `String?` | Opcional | Ficha del paciente |
| `contactoEmergencia` | `String?` | Opcional | Ficha del paciente |
| `fotoBase64` | `String?` | Opcional | Foto en base64 dentro del documento (sin Storage) |
| `cuidadorFcmToken` | `String?` | Opcional | Token FCM del cuidador, espejado aquí para que el paciente pueda enviarle la alerta de 5 días |

El modelo completo está en `paciente.dart:17-26` y `fromMap`/`toMap` en
`paciente.dart:64-93`. `crearPaciente` escribe los opcionales como `null` cuando
no se rellenan (`firestore_service.dart:79-109`).

**`codigoVinculacion` en detalle**

- Formato `MEDI-XXXXXX` sobre el alfabeto `'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'`
  (`vinculacion_service.dart:22`), sin `0/O` ni `1/I` para copiarlo a mano.
- Regex assertion en `test/widget_test.dart:31`:
  `^MEDI-[A-HJ-NP-Z2-9]{6}$`.
- `generarCodigo()` (`vinculacion_service.dart:37-44`) usa `Random.secure()`.
  **No** es un LCG hecho a mano.
- **Solo es único por cuidador.** El chequeo de duplicados usa
  `buscarPacientePorCodigo(codigo, uid)` (`vinculacion_service.dart:63`), que
  filtra por el `cuidadorId` propio. Dos cuidadores pueden tener el mismo código,
  y `vincularDispositivoPorCodigo` (con `limit(1)` y sin filtro de `cuidadorId`)
  devolvería el primero que responda el servidor.
- Se normaliza con `.trim().toUpperCase()` antes de consultar
  (`firestore_service.dart:578` y `:603`).

**`dispositivoVinculadoId` — todos los valores posibles**

| Valor | Significado | Quién lo escribe |
|---|---|---|
| `''` | **Libre**: el paciente puede vincularse | `crearPaciente` (`firestore_service.dart:79`) y `desvincularDispositivo` (`:656-672`) |
| `<uid anónimo>` | **Vinculado** a ese teléfono | `vincularDispositivoPorCodigo` (`:599-650`) |
| `null` | Solo documentos creados **antes** del fix | nadie (legacy) |

> **Trampa de datos.** `estaLibre()` (reglas, líneas 20-22) acepta `null` **o**
> `''`. La vinculación actual ya **no** filtra pacientes por
> `dispositivoVinculadoId == ''`: resuelve el código en `vinculos`, hace un
> `update` directo y deja que la regla valide el documento. Por eso un documento
> legado con `null` también se puede vincular. `crearPaciente` sigue escribiendo
> `''` explícitamente (`firestore_service.dart:103`).

> **Nunca** escribas ahí el `disp-<micros>` de `LocalStore.getDispositivoId()`
> (`local_store.dart:25-33`): las reglas lo comparan contra `request.auth.uid`,
> así que sería rechazado. Ese método además está **muerto** (nadie lo llama).

### Referencias

| Campo | Apunta a |
|---|---|
| `cuidadorId` | `usuarios/{uid}` |
| — | `tratamientos.pacienteId` y `registrosToma.pacienteId` apuntan acá |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read | `isAuthenticated()` **y** (uid == `cuidadorId` **o** uid == `dispositivoVinculadoId`) | 30-32 |
| create | `isAuthenticated()` **y** `cuidadorId == request.auth.uid` **y** `codigoVinculacion != null` **y** `nombre != null` | 33-36 |
| update | `isAuthenticated()` **y** (uid == `cuidadorId` **o** (el nuevo `dispositivoVinculadoId` == `request.auth.uid` **y** el doc estaba libre **y** `codigoVinculacion` sin cambios **y** `cuidadorId` sin cambios)) | 37-44 |
| delete | `isAuthenticated()` **y** uid == `cuidadorId` | 45-46 |

O sea: el paciente (sesión anónima) **no puede** crear ni borrar su propio
documento, y **no puede** desvincularse. Solo el cuidador dueño libera el
código, llamando a `desvincularDispositivo` (que escribe `''`). La rama de
lectura ya **no** incluye documentos libres: el paciente llega al documento por
el índice `vinculos/{codigo}` y, tras el `update`, la lectura directa ya está
autorizada por `dispositivoVinculadoId`. `estaLibre` (líneas 20-22) solo se usa
en la condición de `update`.

### Cómo consultar — lo importante

La regla de `read` (30-32) es una **disyunción de dos ramas**, y Firestore solo
autoriza una *query* si los filtros de la propia query pueden **demostrar** que
todo documento devuelto cumple la regla. Por eso los filtros "redundantes"
**no** se pueden sacar:

| Método | Filtros | Qué rama demuestra | Si sacás el filtro |
|---|---|---|---|
| `streamPacientesDelCuidador` (`:40-48`) | `cuidadorId == uid` | rama 1 | pierde todos tus pacientes |
| `buscarPacientePorCodigo` (`:576-584`) | `codigoVinculacion ==` + `cuidadorId == uid` + `limit(1)` | rama 1 | **403** "Missing or insufficient permissions", incluso para pacientes propios |
| `streamPacientePorDispositivo` (`:50-59`, **muerto**) | `dispositivoVinculadoId ==` + `limit(1)` | rama 2 | — |
| `getPacienteVinculadoParaReingreso` (`:549-563`) | `dispositivoVinculadoId == uid` | rama 2 | **403**; no puede demostrar que el doc es del dispositivo |

- **Con demostrar una sola rama alcanza**; no hacen falta las dos.
- `getPaciente` (`:69-76`) y `streamPacienteDoc` (`:63-67`) usan `.doc(id)`: son
  accesos directos, la regla se evalúa sobre el documento, no hay filtro que
  agregar.
- `vincularDispositivoPorCodigo` (`:599-650`) **no** consulta pacientes por
  `dispositivoVinculadoId == ''`: lee `vinculos/{codigo}`, hace el `update`
  directo y, si la escritura funciona, ya puede leer el documento porque el
  nuevo `dispositivoVinculadoId` es su propio UID.
- **No hace falta índice compuesto**: solo hay igualdades y `limit`, sin
  `orderBy`.
- `vincularDispositivoAPaciente` (`:126-133`) está **muerto** y sería rechazado
  igual: quien llama no es el dueño y el token local no es `request.auth.uid`.

---

## `vinculos/{codigo}`

### ID del documento

= **el código de vinculación normalizado**: `trim().toUpperCase()`, formato
`MEDI-XXXXXX`. No es autogenerado. El índice existe para que el dispositivo
anónimo pueda resolver un código sin poder leer todos los pacientes libres.
`crearPaciente` lo escribe con `.set()` después de crear el paciente
(`firestore_service.dart:111-113`) y `desvincularDispositivo` lo vuelve a
escribir con el código normalizado (`:668-670`).

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Nunca null | → `pacientes/{id}` |

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read | `isAuthenticated()` | 71 |
| create, update | `isAuthenticated()` **y** `pacienteId != null` **y** `esCuidadorDelPaciente(pacienteId)` | 72-74 |
| delete | `isAuthenticated()` **y** `pacienteId != null` **y** `esCuidadorDelPaciente(pacienteId)` | 75-77 |

Cualquier usuario autenticado puede **leer** un código (lo necesita el paciente
anónimo para resolverlo), pero solo el cuidador dueño del paciente puede
crearlo, actualizarlo o borrarlo. `esCuidadorDelPaciente` está en las líneas
10-13.

### Cómo consultar

| Método | Filtros | Índice |
|---|---|---|
| `vincularDispositivoPorCodigo` (`firestore_service.dart:599-650`) | `.doc(codigoNormalizado).get()` | ninguno: acceso directo |
| `crearPaciente` (`:111-113`) | `.doc(codigo).set(...)` | ninguno |
| `desvincularDispositivo` (`:668-670`) | `.doc(codigo).set(...)` | ninguno |

**Código repetido entre cuidadores.** El chequeo de unicidad de
`generarCodigo` solo mira los pacientes del propio cuidador
(`vinculacion_service.dart:60-65`). Dos cuidadores pueden generar el mismo
código; el último `crearPaciente` que escriba `vinculos/{codigo}` repunta el
índice al paciente nuevo. No hay unicidad global.

---

## `tratamientos/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearTratamiento` hace `.add(...)`
(`firestore_service.dart:205-207`).

`actualizarTratamiento` (`:216-220`) hace
`.doc(id).update(tratamiento.toMap())`, o sea un **reemplazo completo**: se
reescriben todos los campos. Por eso el editor conserva explícitamente
`ultimoAvisoSinTomas` (`editar_tratamiento_screen.dart:291-293`).

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Nunca null | → `pacientes/{id}`. **Es el ancla de autorización** de toda la colección |
| `nombreMedicamento` | `String` | Default `''` al leer | Nombre, por ejemplo "Losartán" |
| `fotoBase64` | `String?` | **Puede ser `null`** | Data URI `data:image/jpeg;base64,...` |
| `dosis` | `String` | Default `'1'` al leer | **¡Es texto, no un número!** Se muestra como `"$dosis DOSIS"` |
| `horarios` | `List<Map>` | Default `[]` al leer | Cada elemento es `{hora: "HH:mm", dias: [1..7]}`; ver abajo la compatibilidad con el formato viejo `List<String>` |
| `frecuencia` | `String` | Default `''` al leer | Texto libre: `'Diaria'`, `'Cada 12 h'`, `'Cada 8 h'`, `'Semanal'`, `'Solo cuando sea necesario'`. **Decorativa** |
| `duracion` | `String?` | Opcional | Texto legible (`'7 días'`, `'Continuo'`). No decide la finalización |
| `fechaInicio` | `Timestamp?` (en Dart, `DateTime?`) | Opcional; **null** en documentos viejos | Fecha local **sin hora** desde la que cuenta el tratamiento |
| `duracionDias` | `int?` | Opcional; **null** = continuo o desconocido | Días de duración; junto con `fechaInicio` define la fecha de fin |
| `ultimoAvisoSinTomas` | `Timestamp?` (en Dart, `DateTime?`) | Opcional; **null** = sin aviso pendiente | Fecha local del último push de 5 días sin tomas; evita repetirlo el mismo día y se borra al romper la racha |

Los campos están en `tratamiento.dart:56-67`, se leen en `fromMap`
(`:83-98`) y se escriben siempre en `toMap` (`:140-153`). `fechaInicio` y
`ultimoAvisoSinTomas` se normalizan a fecha local sin hora con `_parseFecha`
(`:100-112`); `duracionDias` se valida como entero positivo (`:114-117`).

**`fotoBase64`**

- La foto va **dentro del documento**, no a Firebase Storage. `ImagenService`
  la recorta a `maxDimension = 800` px y la comprime hasta `maxBytes = 280 * 1024`
  (`imagen_service.dart:12-13`) para no pasar el límite de 1 MB por documento.
- `toMap()` siempre escribe la clave, así que sin foto queda **guardada como
  `null`**, no ausente.
- Todos los consumidores la chequean con `!= null && !isEmpty`
  (`detalle_paciente_screen.dart:223`, `medicamentos_proximos_screen.dart:467`,
  `alarma_screen.dart:91`).
- Se muestra con `MemoryImage` / `Image.memory`
  (`detalle_paciente_screen.dart:225-226`, `medicamentos_proximos_screen.dart:484`,
  `alarma_screen.dart:367`). **Nunca** `NetworkImage` / `Image.network`.

**`fechaInicio`, `duracionDias` y `duracion`**

- `fechaInicio` y `duracionDias` son la fuente real de la vigencia. La fecha de
  fin es **inclusiva**: un tratamiento de 3 días que empieza el lunes termina el
  miércoles (`vigencia_tratamiento.dart:12-22`).
- `duracionDias == null` significa continuo **o** desconocido (documentos
  viejos): en ambos casos no se calcula fecha de fin y el tratamiento se
  considera vigente (`vigencia_tratamiento.dart:24-34`).
- `duracion` es solo el texto legible (`'7 días'`, `'Continuo'`) que se muestra;
  no participa de ningún cálculo (`editar_tratamiento_screen.dart:286-290`).
- El editor solo permite elegir una fecha de inicio hasta hoy
  (`editar_tratamiento_screen.dart:144-158`).

**`ultimoAvisoSinTomas`**

- Solo lo escribe el **paciente** al enviar la alerta de 5 días sin tomas:
  `FirestoreService.marcarAvisoSinTomas` guarda la fecha local sin hora
  (`firestore_service.dart:226-232`).
- Se borra con `FieldValue.delete()` cuando una toma confirmada rompe la racha
  (`firestore_service.dart:235-239`).
- Es el único campo de `tratamientos` que el paciente puede actualizar (ver
  reglas abajo). El cuidador lo conserva al editar el tratamiento
  (`editar_tratamiento_screen.dart:291-293`).

**`frecuencia` es solo decorativa**

El dropdown de `editar_tratamiento_screen.dart:406-415` y `:458-465` ofrece
`Diaria`, `Cada 12 h`, `Cada 8 h`, `Semanal` y `Solo cuando sea necesario`; se
guarda y se muestra, pero
**ninguna lógica lo lee** para calcular dosis. La programación de alarmas y la
detección de tomas pendientes usan **solo `horarios`**
(`editar_tratamiento_screen.dart:220-282`,
`notificaciones_service.dart:601-620`). No construyas nada sobre `frecuencia`
sin revisarlo.

**`dosis` y `horarios`**

- `dosis` se guarda con `dosis.isEmpty ? '1' : dosis`
  (`editar_tratamiento_screen.dart:275`). No la pases por `int.parse` sin guarda.
- `horarios` es una lista de mapas `{hora, dias}` (`tratamiento.dart:11-36`).
  `fromMap` acepta el formato viejo `['HH:mm']` y lo expande a todos los días
  (`tratamiento.dart:119-138`); una lista explícita de días, aunque esté vacía,
  se respeta.
- `hora` se parte con `split(':')` en varios lugares
  (`proxima_toma.dart:50`, `omitidas_service.dart:158`,
  `notificaciones_service.dart:338`). **Mantené el formato `"HH:mm"`** o se
  rompe el agendado.

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |
| — | `registrosToma.tratamientoId` apunta acá |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read | `esCuidadorDelPaciente(resource.data['pacienteId'])` **o** `esDispositivoVinculado(resource.data['pacienteId'])` | 50-51 |
| update | `esCuidadorDelPaciente(...)` **o** (`esDispositivoVinculado(...)` **y** `request.resource.data.diff(resource.data).affectedKeys().hasOnly(['ultimoAvisoSinTomas'])`) | 54-58 |
| create | `esCuidadorDelPaciente(request.resource.data['pacienteId'])` | 59 |
| delete | `esCuidadorDelPaciente(resource.data['pacienteId'])` | 60 |

- El **paciente** puede **leer** los tratamientos de su paciente, pero en
  `update` solo puede tocar `ultimoAvisoSinTomas`. No puede crear ni borrar
  tratamientos, ni cambiar `horarios`, `dosis`, `fechaInicio`, etc.
- Esa restricción es exactamente la que necesitan `marcarAvisoSinTomas`
  (`firestore_service.dart:226-232`) y `limpiarAvisoSinTomas` (`:235-239`).
  Borrar el campo con `FieldValue.delete()` también cuenta como una sola clave
  afectada.
- El **cuidador** conserva el CRUD completo.
- En `create` se lee `request.resource.data` porque **`resource` es `null`**.
  En el resto, `resource` es el doc actual.
- Las dos funciones helper (líneas 10-18) hacen un `get()` del documento
  `pacientes/{id}`, así que el llamador **también** tiene que poder leer ese
  paciente.

### Cómo consultar

| Método | Filtros | Índice |
|---|---|---|
| `streamTratamientosDePaciente` (`firestore_service.dart:180-189`) | `pacienteId ==` | no necesita |
| `detalle_paciente_screen.dart:185-186` | `pacienteId ==` (stream crudo, no el service) | no necesita |

- El `where('pacienteId', ...)` es **lo que hace resoluble** el `get()` que
  hacen los helpers. Sin él, la query no puede probarse contra la regla.
- No hace falta un `where` extra por `dispositivoVinculadoId`: los helpers
  hacen un `get()` por documento (evaluado por documento), no forman parte del
  conjunto de filtros de la query.
- Una sola igualdad, sin `orderBy` → **no** hace falta índice compuesto.

---

## `registrosToma/{id}`

### ID del documento

= **autogenerado por Firestore** en confirmaciones y posposiciones:
`crearRegistroToma` hace `.add(...)` (`firestore_service.dart:262-284`). La
reconciliación de olvidadas usa un **id determinista** con `.set()` para que dos
pasadas solapadas no creen dos documentos (`firestore_service.dart:279-280` y
`omitidas_service.dart:250-252`).

`confirmarToma` (`:287-295`) apunta a un doc existente con `.doc(id).update(...)`,
pero está **muerto**: nadie lo llama.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Default `''` al leer | → `pacientes/{id}`. **Ancla de autorización** |
| `tratamientoId` | `String` | Default `''` al leer | → `tratamientos/{id}` |
| `horaProgramada` | `Timestamp` (en Dart, `DateTime`) | Nunca null | Hora de la toma; se ordena y se filtra por rango |
| `horaConfirmacion` | `Timestamp?` (en Dart, `DateTime?`) | **Puede ser `null`** | Momento de confirmación; `null` si `estado` es `pendiente` u `olvidó` (`registro_toma.dart:54-61`) |
| `estado` | `String` | Nunca null | Ver tabla abajo |

**`estado`: el miembro del enum y el string guardado NO coinciden**

El enum Dart es `EstadoToma`; lo que se persiste es `EstadoTomaExt.nombre`
(`registro_toma.dart:12-26`):

| Miembro del enum | String en Firestore |
|---|---|
| `pendiente` | `pendiente` |
| `tomada` | **`tomó`** |
| `tardia` | **`tardó`** |
| `olvidada` | **`olvidó`** |
| `pospuesta` | `pospuesta` |

`EstadoTomaExt.fromNombre` (`:28-41`) mapea cualquier string desconocido a
`pendiente` (rama `default`).

`detalle_paciente_screen.dart:975-981` **hardcodea** los literales `'tomó'`,
`'tardó'`, `'olvidó'`: actualizalo si agregás un estado.

**Qué escribe realmente el código hoy**

Hoy se producen los cuatro estados no pendientes:

- `tomó` o `tardó` al confirmar en la pantalla de alarma
  (`alarma_screen.dart:147-170`); `tardó` si `now - horaProgramada > 15 min`.
- `pospuesta` al pulsar "Recordar" (`alarma_screen.dart:191-203`).
- `olvidó` desde la reconciliación de tomas perdidas
  (`omitidas_service.dart:330-335`), con `horaConfirmacion = null`.

`pendiente` sigue sin escribirse nunca (es el default del modelo). Los
contadores "Tomadas/Tardías/Olvidadas" de `detalle_paciente_screen.dart:975-981`
comparan los literales `'tomó'`, `'tardó'` y `'olvidó'` a mano.

**No hay un doc por dosis en el camino normal**

"YA" y "Recordar" siempre crean un `.add()` nuevo, nunca actualizan un
pendiente. La excepción es la toma olvidada, que usa un id determinista para ser
idempotente. `_yaConfirmada` (`medicamentos_proximos_screen.dart:240-252`)
trata `pospuesta` como *no confirmada*, así que una dosis pospuesta vuelve a
sonar. No armes queries que asuman unicidad por
(`tratamientoId`, `horaProgramada`) salvo para las olvidadas.

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |
| `tratamientoId` | `tratamientos/{id}` |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read, update, delete | `esCuidadorDelPaciente(resource.data['pacienteId'])` **o** `esDispositivoVinculado(...)` | 64-65 |
| create | `esCuidadorDelPaciente(request.resource.data['pacienteId'])` **o** `esDispositivoVinculado(...)` | 66-67 |

El paciente **crea** sus propios registros al confirmar o posponer, y la
reconciliación escribe las olvidadas; el cuidador los **lee** en tiempo real
para el dashboard.

### Cómo consultar — acá sí hacen falta índices compuestos

`firestore.indexes.json` ya contiene las definiciones de los compuestos que usa
el código (líneas 2-67), pero en este proyecto los índices de producción se han
gestionado desde la consola de Firebase. Un `FAILED_PRECONDITION` /
"requires an index" se resuelve creando el índice **en la consola**; no asumas
que desplegar el archivo del repo lo crea.

| Método | Filtros | Índice compuesto necesario |
|---|---|---|
| `streamRegistrosDePaciente` (`firestore_service.dart:326-340`) | `pacienteId ==` + `orderBy('horaProgramada', desc)` + `limit` | `(pacienteId ASC, horaProgramada DESC)` |
| `streamRegistrosDePacientes` (`:378-406`) | `pacienteId whereIn grupo` + `orderBy('horaProgramada', desc)` + `limit` | el mismo de arriba |
| `detalle_paciente_screen.dart:942-947` | `pacienteId ==` + `orderBy('horaProgramada', desc)` + `limit(10)` | el mismo de arriba |
| `streamTomasPendientesHoy` (`firestore_service.dart:449-467`) | `pacienteId ==` + `tratamientoId ==` + `horaProgramada >=` + `horaProgramada <` | `(pacienteId ASC, tratamientoId ASC, horaProgramada ASC)` |
| `getRegistrosEnRango` (`:312-323`) | `pacienteId ==` + `horaProgramada >=` + `horaProgramada <` | `(pacienteId ASC, horaProgramada ASC)` |
| `getHistorialDeTratamiento` (`:482-534`) | `pacienteId ==` + `tratamientoId ==` + rango `horaProgramada` + `orderBy` desc + `limit` | `(pacienteId ASC, tratamientoId ASC, horaProgramada DESC)`; si falta, cae al ASC en memoria |

- `streamRegistrosDePacientes` trocea los ids **de a 10**
  (`:400-403`) y fusiona los streams con `_fusionarStreams` (`:410-445`), que
  ordena por `horaProgramada` desc y corta en `limite`. El troceado es
  conservador: Firestore admite hasta 30 valores en un `in`, y el código usa
  10.
- El filtro por `tratamientoId` de `streamTomasPendientesHoy` **no** lo pide la
  regla (las reglas solo se anclan en `pacienteId`): es un requisito **de
  índice**, porque ensancha el compuesto. El rango va sobre el **último**
  campo, en intervalo semiabierto `[hoy, mañana)`.
- El `where('pacienteId', ...)` sigue siendo **obligatorio** por la misma razón
  que en `tratamientos`: es lo que hace resoluble el `get()` de los helpers.

---

## Notificaciones locales

Los canales se crean en `NotificacionesService._crearCanales`
(`notificaciones_service.dart:218-274`) y sus ids están en `:50-54`. Los ids de
las notificaciones programadas son **deterministas** para poder cancelarlas sin
guardar nada en Firestore.

| Tipo | Id / rango | Canal | Cuándo |
|---|---|---|---|
| Alarma principal | `idDeAlarma` = `hashEstable("<tratamientoId>|<hora>|<día>")`, positivo en `[1, 0x7FFFFFFF]` (`:387-390`) | `alarmas_medicamentos` | Semanal, en la hora exacta; abre pantalla completa |
| Aviso previo | `[-0x0FFFFFFF, -1]` (`:409-410`, `:423-425`) | `avisos_previos` | Semanal, 5 min antes |
| Felicitación | `[-0x1FFFFFFF, -0x10000000]` (`:411-412`, `:428-434`) | `felicitaciones` | Inmediata al confirmar; no se programa |
| Recordatorio tardío semanal | `[-0x27FFFFFF, -0x20000000]` (`:413-414`, `:437-447`) | `recordatorios_tardios` | Semanal, 15 min después de la toma |
| Recordatorio tardío puntual | `[-0x2FFFFFFF, -0x28000000]` (`:415-416`, `:450-455`) | `recordatorios_tardios` | Una sola vez, al posponer |
| Aviso local del cuidador | Positivo sin subrango reservado: `r.id.hashCode & 0x7FFFFFFF` o `millisecondsSinceEpoch & 0x7FFFFFFF` (`dashboard_screen.dart:124`, `:133`) | `alertas_cuidador` | Solo con la app visible (`dashboard_screen.dart:122-150`) |

`hashEstable` es un polinomio de 31 bits con `0` reservado
(`hash_estable.dart:18-23`). El `0` nunca se usa como id. La alarma principal
usa ids positivos; los cuatro tipos nuevos usan subrangos negativos para no
chocar con ella (`notificaciones_service.dart:392-416`).

## Push FCM: la única salida externa

El **único** envío FCM que queda es la alerta de **5 días sin tomas**:

- Cálculo puro: `AlertaSinTomasService.hayAlerta` (`alerta_sin_tomas_service.dart:22-40`)
  exige tratamiento vigente, `fechaInicio` conocido y que los últimos **5 días
  programados** anteriores a hoy no tengan ninguna confirmación. Se saltan los
  días sin toma programada; `pospuesta` no cuenta y `olvidó` tampoco
  (`:111-120`).
- Disparo: `OmitidasService.reconciliar` evalúa la alerta después de escribir
  las tomas olvidadas (`omitidas_service.dart:358-366`) y llama a
  `_evaluarAlertasSinTomas` (`:398-463`).
- Antes de enviar, escribe `ultimoAvisoSinTomas` para que dos reconciliaciones
  solapadas no dupliquen el push (`omitidas_service.dart:442-452`). Si el
  tratamiento sale de la alerta (una toma confirmada), borra el campo
  (`:413-430`).
- Envío: `PushService.notificarAlertaSinTomas` (`push_service.dart:171-231`)
  lee `pacientes/{id}.cuidadorFcmToken` (`:183-185`), firma un JWT con la cuenta
  de servicio y hace `POST .../messages:send` (`:190-219`). El cuerpo lleva
  nombre del paciente y del medicamento (`:199-205`) y el canal
  `alertas_cuidador` (`:206-214`).
- **No hay otro camino FCM.** No existe `notificarConfirmacion` ni ningún otro
  `messages:send`; el dashboard solo muestra notificaciones locales mientras la
  app está visible (`dashboard_screen.dart:122-150`).
- Respaldo en la app del cuidador: `_AvisoSinTomas` recalcula lo mismo al abrir
  el detalle del paciente y pinta una tarjeta, **sin enviar FCM**
  (`detalle_paciente_screen.dart:373-484`).

⚠️ **Seguridad:** la credencial de la cuenta de servicio viaja dentro del APK
(`push_service.dart:32`, `assets/secrets/fcm_service_account.json`). Es
extraíble; el rol debe limitarse a `cloudmessaging.messages.create`. La solución
real sería un proxy/servidor, no mover el archivo.

---

## Diagrama de relaciones

```
                        Firebase Auth
                              │
              uid            │            uid anónimo
              (credenciales) │            (signInAnonymously)
                              ▼            │
                    ┌────────────────┐   │
                    │  usuarios/{uid}│   │  ← doc = UID de Auth, no autogenerado
                    ├────────────────┤   │
                    │ uid      Str   │   │
                    │ nombre    Str  │   │
                    │ correo    Str  │   │
                    └───────┬────────┘   │
                            │            │
                 cuidadorId │            │
                            ▼            │
        ┌───────────────────────────────────────┐
        │            pacientes/{id}             │  ← id autogenerado por .add()
        ├───────────────────────────────────────┤
        │ nombre             String             │
        │ cuidadorId         String  ───────────┼──► usuarios/{uid}
        │ codigoVinculacion  String  MEDI-XXXXXX│
        │ dispositivoVinculadoId String         │◄──┘ '' = libre
        │ cuidadorFcmToken   String?            │
        └────┬─────────────────────────┬────────┘
             │                         │
   pacienteId│                         │pacienteId
             ▼                         ▼
   ┌──────────────────────┐  ┌──────────────────────────────┐
   │ tratamientos/{id}    │  │       registrosToma/{id}     │
   ├──────────────────────┤  ├──────────────────────────────┤
   │ pacienteId      Str  │  │ pacienteId      Str  ────────┼──► pacientes/{id}
   │ nombreMedicamento    │  │ tratamientoId    Str  ────────┼──► tratamientos/{id}
   │ fotoBase64   String?  │  │ horaProgramada  Timestamp    │
   │ dosis         Str    │  │ horaConfirmacion Timestamp?  │
   │ horarios   List<Map> │  │ estado          String       │
   │ frecuencia    Str    │  └──────────────────────────────┘
   │ fechaInicio DateTime?│
   │ duracionDias Int?    │
   │ ultimoAvisoSinTomas  │
   └──────────────────────┘

   vinculos/{codigo} ── pacienteId ──► pacientes/{id}
```

Las flechas son punteros unidireccionales: el documento hijo lleva el ID del
padre. No hay subcolecciones anidadas ni documentos de contraparte. El índice
`vinculos/{codigo}` apunta al paciente y es la puerta de entrada del dispositivo
anónimo.

## Puntos de autorización, de un vistazo

- `pacientes` es el **único** lugar donde vive la identidad de los dos roles.
  Todo lo demás se autoriza preguntando, mediante un `get()` al `pacientes` que
  corresponde, quién es el `cuidadorId` y quién es el `dispositivoVinculadoId`.
- Las funciones helper **deben** quedar dentro de
  `match /databases/{database}/documents` (líneas 26-112): fuera de ese bloque
  pierden el scope de `get()` y `$(database)`, y las reglas fallan en runtime.
- No hay Cloud Functions que validen nada: si una regla no lo permite, el
  cliente simplemente recibe `permission-denied`. Por eso cada query replica
  la condición de la regla en sus propios `where`.
