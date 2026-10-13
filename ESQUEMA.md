# ESQUEMA.md — Modelo de datos de Firestore

Documento derivado **exclusivamente** del código: `lib/models/*.dart`,
`lib/services/firestore_service.dart` y `firestore.rules`. Si algo no está
mencionado acá, no existe en el modelo.

No hay backend: no hay Cloud Functions, ni FCM, ni Firebase Storage. Todo se
lee y escribe desde el cliente, y la seguridad vive **enteramente** en
`firestore.rules` (proyecto `mediplan-35953`).

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
`auth_service.dart:78-85` usa `.collection('usuarios').doc(user.uid).set(...)`.

Se escribe **solo si el documento no existe** (`auth_service.dart:81`,
`if (!doc.exists)`), así que el perfil nunca se actualiza después de creado.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `uid` | `String` | Nunca null | UID de Auth. **Duplica el ID del documento.** |
| `nombre` | `String` | Nunca null. Puede ser el literal `'Cuidador'` | `nombre ?? user.displayName ?? 'Cuidador'` (`auth_service.dart:87`) |
| `correo` | `String` | Nunca null. **Puede ser `''`** | `user.email ?? ''`; vacío si la cuenta no tiene correo |

`Usuario.fromMap` (`usuario.dart:13-19`) devuelve `''` para cualquier campo
ausente, así que un documento corrupto no rompe la app, devuelve strings vacíos.

### Referencias

Ninguna. Esta colección es la **raíz**: el resto la apunta, no al revés.

`usuarios/{uid}` ← `pacientes.cuidadorId`

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read, create, update | `isAuthenticated() && request.auth.uid == uid` | 57 |
| delete | `if false` — **nadie puede borrar** | 58 |

`isAuthenticated()` (líneas 32-34) solo exige `request.auth != null`.

### Cómo consultar

- La app **nunca lista** `usuarios`: solo hace un `doc(uid).get()` directo en
  `auth_service.dart:77-80`, que cumple la regla porque el uid es el propio.
- Un cuidador **no puede leer** el `usuarios` de otro cuidador. Ni siquiera el
  paciente puede leer nada acá.
- No hace falta ningún filtro `where`: el acceso es por ID directo.

---

## `pacientes/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearPaciente` hace `.add(...)`
(`firestore_service.dart:70`).

`Paciente.toMap()` (`paciente.dart:42-49`) **no** incluye el campo `id`: el `id`
del modelo es solo el ID del documento, y se rellena al leer con
`Paciente.fromMap(snap.id, snap.data())`.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `nombre` | `String` | Nunca null — la regla de `create` lo exige (línea 75) | Nombre del paciente |
| `cuidadorId` | `String` | Nunca null | → `usuarios/{uid}`. En `create` debe ser `request.auth.uid` (línea 73) |
| `codigoVinculacion` | `String` | Nunca null — la regla lo exige (línea 74) | `MEDI-XXXXXX`, el código que el paciente tipea |
| `dispositivoVinculadoId` | `String` | **`''` = libre.** Puede ser `null` en documentos viejos | UID anónimo del Auth del teléfono del paciente |

**`codigoVinculacion` en detalle**

- Formato `MEDI-XXXXXX` sobre el alfabeto `'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'`
  (`vinculacion_service.dart:22`), sin `0/O` ni `1/I` para copiarlo a mano.
- Regex assertion en `test/widget_test.dart:25`:
  `^MEDI-[A-HJ-NP-Z2-9]{6}$`.
- `generarCodigo()` (`vinculacion_service.dart:35-48`) es un LCG de 48 bits
  hecho a mano, sembrado con `microsecondsSinceEpoch`. **No** es
  `Random.secure()`.
- **Solo es único por cuidador.** El chequeo de duplicados usa
  `buscarPacientePorCodigo(codigo, uid)` (`vinculacion_service.dart:60`), que
  filtra por el `cuidadorId` propio. Dos cuidadores pueden tener el mismo código,
  y `vincularDispositivoPorCodigo` (con `limit(1)` y sin filtro de `cuidadorId`)
  devolvería el primero que responda el servidor.
- Se normaliza con `.trim().toUpperCase()` antes de consultar
  (`firestore_service.dart:296` y `:322`).

**`dispositivoVinculadoId` — todos los valores posibles**

| Valor | Significado | Quién lo escribe |
|---|---|---|
| `''` | **Libre**: el paciente puede vincularse | `crearPaciente` (`:79`) y `desvincularDispositivo` (`:346`) |
| `<uid anónimo>` | **Vinculado** a ese teléfono | `vincularDispositivoPorCodigo` (`:332`) |
| `null` | Solo documentos creados **antes** del fix | nadie (legacy) |

> **Trampa de datos.** `estaLibre()` (reglas, línea 52) acepta `null` **o** `''`,
> pero el filtro `where('dispositivoVinculadoId', isEqualTo: '')` de
> `vincularDispositivoPorCodigo` (`:323`) **no** matchea `null` (en Firestore,
> `null` es un filtro unario aparte). Por eso un paciente con ese campo en
> `null` devuelve "Código inválido". Ojo al crear docs a mano desde la consola.

> **Nunca** escribas ahí el `disp-<micros>` de `LocalStore.getDispositivoId()`
> (`local_store.dart:15-23`): las reglas lo comparan contra `request.auth.uid`,
> así que sería rechazado. Ese método además está **muerto** (nadie lo llama).

### Referencias

| Campo | Apunta a |
|---|---|
| `cuidadorId` | `usuarios/{uid}` |
| — | `tratamientos.pacienteId` y `registrosToma.pacienteId` apuntan acá |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read | `isAuthenticated()` **y** (uid == `cuidadorId` **o** uid == `dispositivoVinculadoId` **o** `estaLibre(dispositivoVinculadoId)`) | 66-69 |
| create | `isAuthenticated()` **y** `cuidadorId == request.auth.uid` **y** `codigoVinculacion != null` **y** `nombre != null` | 72-75 |
| update | `isAuthenticated()` **y** (uid == `cuidadorId` **o** (el nuevo `dispositivoVinculadoId` == `request.auth.uid` **y** el doc estaba libre **y** `codigoVinculacion` sin cambios **y** `cuidadorId` sin cambios)) | 82-89 |
| delete | `isAuthenticated()` **y** uid == `cuidadorId` | 90-91 |

O sea: el paciente (sesión anónima) **no puede** crear ni borrar su propio
documento, y **no puede** desvincularse. Solo el cuidador dueño libera el
código, llamando a `desvincularDispositivo` (que escribe `''`).

### Cómo consultar — lo importante

La regla de `read` (66-69) es una **disyunción de tres ramas**, y Firestore solo
autoriza una *query* si los filtros de la propia query pueden **demostrar** que
todo documento devuelto cumple la regla. Por eso los filtros "redundantes"
**no** se pueden sacar:

| Método | Filtros | Qué rama demuestra | Si sacás el filtro |
|---|---|---|---|
| `streamPacientesDelCuidador` (`:27-34`) | `cuidadorId == uid` | rama 1 | pierde todos tus pacientes |
| `buscarPacientePorCodigo` (`:294-302`) | `codigoVinculacion ==` + `cuidadorId == uid` | rama 1 | **403** "Missing or insufficient permissions", incluso para pacientes propios |
| `vincularDispositivoPorCodigo` (`:320-337`) | `codigoVinculacion ==` + `dispositivoVinculadoId == ''` | rama 3 (`estaLibre`) | **siempre denegado**; el paciente no es el cuidador |
| `streamPacientePorDispositivo` (`:36-44`, **muerto**) | `dispositivoVinculadoId ==` + `limit(1)` | rama 2 | — |

- **Con demostrar una sola rama alcanza**; no hacen falta las tres.
- `getPaciente` (`:53-57`) y `streamPacienteDoc` (`:48-51`) usan `.doc(id)`: son
  accesos directos, la regla se evalúa sobre el documento, no hay filtro que
  agregar.
- `limit(1)` en las dos búsquedas de código: si hubiera duplicados, gana el
  que devuelva el servidor.
- **No hace falta índice compuesto**: solo hay igualdades y `limit`, sin
  `orderBy`.
- `vincularDispositivoAPaciente` (`:86-93`) está **muerto** y sería rechazado
  igual: quien llama no es el dueño y el token local no es `request.auth.uid`.

---

## `tratamientos/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearTratamiento` hace `.add(...)`
(`firestore_service.dart:113`).

`actualizarTratamiento` (`:123-125`) hace `.doc(id).update(tratamiento.toMap())`,
o sea un **reemplazo completo**: se reescriben todos los campos.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Nunca null | → `pacientes/{id}`. **Es el ancla de autorización** de toda la colección |
| `nombreMedicamento` | `String` | Default `''` al leer | Nombre, por ejemplo "Losartán" |
| `fotoBase64` | `String?` | **Puede ser `null`** | Data URI `data:image/jpeg;base64,...` |
| `dosis` | `String` | Default `'1'` al leer | **¡Es texto, no un número!** Se muestra como `"$dosis DOSIS"` |
| `horarios` | `List<String>` | Default `[]` al leer | Horarios `"HH:mm"` en 24 h, p. ej. `["08:00","20:00"]` |
| `frecuencia` | `String` | Default `''` al leer | Texto libre: `'Diaria'`, `'Cada 12 h'`, `'Cada 8 h'`, `'Semanal'` |

**`fotoBase64`**

- La foto va **dentro del documento**, no a Firebase Storage. `ImagenService`
  la recorta a `maxDimension = 800` px y la comprime hasta `maxBytes = 280 * 1024`
  (`imagen_service.dart:12-13`) para no pasar el límite de 1 MB por documento.
- `toMap()` siempre escribe la clave, así que sin foto queda **guardada como
  `null`**, no ausente.
- Todos los consumidores la chequean con `!= null && !isEmpty`
  (`detalle_paciente_screen.dart:130`, `medicamentos_proximos_screen.dart:255`,
  `alarma_screen.dart:151`).
- Se muestra con `MemoryImage` / `Image.memory`
  (`detalle_paciente_screen.dart:132-134`, `medicamentos_proximos_screen.dart:267`).
  **Nunca** `NetworkImage` / `Image.network`.

**`frecuencia` es solo decorativa**

El dropdown de `editar_tratamiento_screen.dart:185-190` ofrece exactamente
`Diaria`, `Cada 12 h`, `Cada 8 h`, `Semanal`; se guarda y se muestra, pero
**ninguna lógica lo lee** para calcular dosis. La programación de alarmas y la
detección de tomas pendientes usan **solo `horarios`**
(`editar_tratamiento_screen.dart:151` y `:164-177`,
`medicamentos_proximos_screen.dart:61-81`). No construyas nada sobre `frecuencia`
sin revisarlo.

**`dosis` y `horarios`**

- `dosis` se guarda con `dosis.isEmpty ? '1' : dosis`
  (`editar_tratamiento_screen.dart:137`). No la pases por `int.parse` sin guarda.
- `horarios` se parte con `split(':')` en varios lugares
  (`medicamentos_proximos_screen.dart:63` y `:225`,
  `notificaciones_service.dart:78`). **Mantené el formato `"HH:mm"`** o se rompe
  el agendado.

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |
| — | `registrosToma.tratamientoId` apunta acá |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read, update, delete | `esCuidadorDelPaciente(resource.data['pacienteId'])` **o** `esDispositivoVinculado(resource.data['pacienteId'])` | 98-99 |
| create | `esCuidadorDelPaciente(request.resource.data['pacienteId'])` **o** `esDispositivoVinculado(request.resource.data['pacienteId'])` | 100-101 |

- En `create` se lee `request.resource.data` porque **`resource` es `null`**
  (comentario en las líneas 95-96). En el resto, `resource` es el doc actual.
- Las dos funciones helper (líneas 37-48) hacen un `get()` del documento
  `pacientes/{id}`, así que el llamador **también** tiene que poder leer ese
  paciente. El paciente llega acá por `esDispositivoVinculado`, igual que el
  cuidador por `esCuidadorDelPaciente`: **ambos roles tienen CRUD completo**
  sobre los tratamientos de su paciente (incluido `delete`).

### Cómo consultar

| Método | Filtros | Índice |
|---|---|---|
| `streamTratamientosDePaciente` (`:103-110`) | `pacienteId ==` | no necesita |
| `detalle_paciente_screen.dart:98-100` | `pacienteId ==` (stream crudo, no el service) | no necesita |

- El `where('pacienteId', ...)` es **lo que hace resoluble** el `get()` que
  hacen los helpers. Sin él, la query no puede probarse contra la regla.
- No hace falta un `where` extra por `dispositivoVinculadoId`: los helpers
  hacen un `get()` por documento (evaluado por documento), no forman parte del
  conjunto de filtros de la query.
- Una sola igualdad, sin `orderBy` → **no** hace falta índice compuesto.

---

## `registrosToma/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearRegistroToma` hace `.add(...)`
(`firestore_service.dart:147`).

`confirmarToma` (`:159-167`) apunta a un doc existente con `.doc(id).update(...)`,
pero está **muerto**: nadie lo llama.

### Campos

| Campo | Tipo | ¿Null / vacío? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Default `''` al leer | → `pacientes/{id}`. **Ancla de autorización** |
| `tratamientoId` | `String` | Default `''` al leer | → `tratamientos/{id}` |
| `horaProgramada` | `Timestamp` (en Dart, `DateTime`) | Nunca null | Hora de la toma; se ordena y se filtra por rango |
| `horaConfirmacion` | `Timestamp?` (en Dart, `DateTime?`) | **Puede ser `null`** | Momento de confirmación; `null` solo si `estado == pendiente` (`:152-153`) |
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

`detalle_paciente_screen.dart:345-347` **hardcodea** los literales `'tomó'`,
`'tardó'`, `'olvidó'`: actualizalo si agregás un estado.

**Qué escribe realmente el código hoy**

Solo `tomó` (`alarma_screen.dart:104`) y `pospuesta` (`alarma_screen.dart:119`),
ambos vía `crearRegistroToma` → `.add()`. **`tardó` y `olvidó` no los produce
ningún camino de código**, así que los contadores "Tardías" y "Olvidadas" de
`detalle_paciente_screen.dart:346-347` dan siempre 0. `pendiente` tampoco se
escribe nunca (es el default de `:144` pero ningún call site lo usa), y por
consiguiente **`horaConfirmacion` nunca es `null` en la práctica**, aunque el
modelo y las reglas lo permitan.

**No hay un doc por dosis**

"YA" y "Recordar" siempre crean un `.add()` nuevo, nunca actualizan un
pendiente. Y `_yaConfirmada` (`medicamentos_proximos_screen.dart:99-111`) trata
`pospuesta` como *no confirmada*, así que una dosis pospuesta vuelve a sonar.
No armes queries que asuman unicidad por (`tratamientoId`, `horaProgramada`).

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |
| `tratamientoId` | `tratamientos/{id}` |

### Reglas de seguridad (`firestore.rules`)

| Operación | Condición | Línea |
|---|---|---|
| read, update, delete | `esCuidadorDelPaciente(resource.data['pacienteId'])` **o** `esDispositivoVinculado(...)` | 108-109 |
| create | `esCuidadorDelPaciente(request.resource.data['pacienteId'])` **o** `esDispositivoVinculado(...)` | 110-111 |

Idéntico a `tratamientos`. El paciente **crea** sus propios registros al
confirmar, y el cuidador los **lee** en tiempo real para el dashboard.

### Cómo consultar — acá sí hacen falta índices compuestos

`firestore.indexes.json` está **vacío**; los índices compuestos existen solo en
la consola de Firebase. Un `FAILED_PRECONDITION` / "requires an index" se
resuelve creando el índice **en la consola**; desplegar el archivo del repo no
ayuda.

| Método | Filtros | Índice compuesto necesario |
|---|---|---|
| `streamRegistrosDePaciente` (`:170-182`) | `pacienteId ==` + `orderBy('horaProgramada', desc)` + `limit` | `(pacienteId ASC, horaProgramada DESC)` |
| `streamRegistrosDePacientes` (`:190-216`) | `pacienteId whereIn grupo` + `orderBy('horaProgramada', desc)` + `limit` | el mismo de arriba |
| `detalle_paciente_screen.dart:322-326` | `pacienteId ==` + `orderBy('horaProgramada', desc)` + `limit(10)` | el mismo de arriba |
| `streamTomasPendientesHoy` (`:260-276`) | `pacienteId ==` + `tratamientoId ==` + `horaProgramada >=` + `horaProgramada <` | `(pacienteId ASC, tratamientoId ASC, horaProgramada ASC)` |

- `streamRegistrosDePacientes` trocea los ids **de a 10**
  (`:206-213`) y fusiona los streams con `_fusionarStreams` (`:220-256`), que
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
   │ horarios  List<String>│ │ estado          String       │
   │ frecuencia    Str    │  └──────────────────────────────┘
   └──────────────────────┘
```

Las dos flechas de la derecha son punteros unidireccionales: el documento hijo
lleva el ID del padre. No hay subcolecciones anidadas ni documentos de
contraparte.

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
