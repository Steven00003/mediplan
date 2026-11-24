# ESQUEMA.md â€” Modelo de datos de Firestore

Documento derivado **exclusivamente** del cÃ³digo: `lib/models/*.dart`,
`lib/services/firestore_service.dart` y `firestore.rules`. Si algo no estÃ¡
mencionado acÃ¡, no existe en el modelo.

No hay backend con Cloud Functions ni Firebase Storage. Todo el modelo se lee y
escribe desde el cliente, y la seguridad vive **enteramente** en
`firestore.rules` (proyecto `mediplan-35953`). La Ãºnica llamada a un servidor
externo es el push FCM HTTP v1 que el dispositivo del paciente envÃ­a al cuidador
para la alerta de **5 dÃ­as sin tomas** (ver [Push FCM](#push-fcm-la-Ãºnica-salida-externa)).
Ese push no escribe datos: la fuente de verdad sigue siendo Firestore.

## Los dos roles y sus dos UIDs

| Rol | Firebase Auth | DÃ³nde aparece su UID |
|---|---|---|
| Doctor / Cuidador | correo/contraseÃ±a o Google, con credenciales | `usuarios/{uid}`, `pacientes.cuidadorId` |
| Paciente | `signInAnonymously()`, **sin credenciales** | `pacientes.dispositivoVinculadoId` |

El paciente no tiene cuenta: su UID anÃ³nimo **es** su identidad de dispositivo.
Las reglas comparan ese UID contra `request.auth.uid`.

---

## `usuarios/{uid}`

### ID del documento

= **el UID de Firebase Auth**, no autogenerado.
`auth_service.dart:84-91` usa `.collection('usuarios').doc(user.uid).set(...)`.

Se escribe **solo si el documento no existe** (`auth_service.dart:83`,
`if (!doc.exists)`), asÃ­ que el perfil nunca se actualiza despuÃ©s de creado.

### Campos

| Campo | Tipo | Â¿Null / vacÃ­o? | Significado |
|---|---|---|---|
| `uid` | `String` | Nunca null | UID de Auth. **Duplica el ID del documento.** |
| `nombre` | `String` | Nunca null. Puede ser el literal `'Cuidador'` | `nombre ?? user.displayName ?? 'Cuidador'` (`auth_service.dart:89`) |
| `correo` | `String` | Nunca null. **Puede ser `''`** | `user.email ?? ''`; vacÃ­o si la cuenta no tiene correo |

`Usuario.fromMap` (`usuario.dart:13-19`) devuelve `''` para cualquier campo
ausente, asÃ­ que un documento corrupto no rompe la app, devuelve strings vacÃ­os.

### Referencias

Ninguna. Esta colecciÃ³n es la **raÃ­z**: el resto la apunta, no al revÃ©s.

`usuarios/{uid}` â† `pacientes.cuidadorId`

### Reglas de seguridad (`firestore.rules`)

| OperaciÃ³n | CondiciÃ³n | LÃ­nea |
|---|---|---|
| read, create, update | `isAuthenticated() && request.auth.uid == uid` | 25 |
| delete | `if false` â€” **nadie puede borrar** | 26 |

`isAuthenticated()` (lÃ­neas 6-8) solo exige `request.auth != null`.

### CÃ³mo consultar

- La app **nunca lista** `usuarios`: solo hace un `doc(uid).get()` directo en
  `auth_service.dart:79-82`, que cumple la regla porque el uid es el propio.
- Un cuidador **no puede leer** el `usuarios` de otro cuidador. Ni siquiera el
  paciente puede leer nada acÃ¡.
- No hace falta ningÃºn filtro `where`: el acceso es por ID directo.

---

## `pacientes/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearPaciente` hace `.add(...)`
(`firestore_service.dart:124`).

`Paciente.toMap()` (`paciente.dart:81-93`) **no** incluye el campo `id`: el `id`
del modelo es solo el ID del documento, y se rellena al leer con
`Paciente.fromMap(snap.id, snap.data())`.

### Campos

| Campo | Tipo | Â¿Null / vacÃ­o? | Significado |
|---|---|---|---|
| `nombre` | `String` | Nunca null â€” la regla de `create` lo exige (lÃ­nea 36) | Nombre del paciente |
| `cuidadorId` | `String` | Nunca null | â†’ `usuarios/{uid}`. En `create` debe ser `request.auth.uid` (lÃ­nea 34) |
| `codigoVinculacion` | `String` | Nunca null â€” la regla lo exige (lÃ­nea 35) | `MEDI-XXXXXX`, el cÃ³digo que el paciente tipea |
| `dispositivoVinculadoId` | `String` | **`''` = libre.** Puede ser `null` en documentos viejos | UID anÃ³nimo del Auth del telÃ©fono del paciente |
| `edad` | `int?` | Opcional | Ficha del paciente |
| `condicion` | `String?` | Opcional | Ficha del paciente |
| `contactoEmergencia` | `String?` | Opcional | Ficha del paciente |
| `fotoBase64` | `String?` | Opcional | Foto en base64 dentro del documento (sin Storage) |
| `cuidadorFcmToken` | `String?` | Opcional | Token FCM del cuidador, espejado aquÃ­ para que el paciente pueda enviarle la alerta de 5 dÃ­as |
| `dispositivoFcmToken` | `String?` | Opcional | Token FCM del telÃ©fono del paciente; solo el dispositivo vinculado lo escribe. Permite al cuidador avisar de cambios de tratamiento en segundo plano |

El modelo completo estÃ¡ en `paciente.dart:17-26` y `fromMap`/`toMap` en
`paciente.dart:64-93`. `crearPaciente` escribe los opcionales como `null` cuando
no se rellenan (`firestore_service.dart:110-154`).

**EdiciÃ³n de la ficha.** El botÃ³n de lÃ¡piz del detalle abre
`EditarPacienteScreen` y guarda con `actualizarFichaPaciente`
(`firestore_service.dart`). Ese `update` escribe **solo** `nombre`, `edad`,
`condicion`, `contactoEmergencia` y `fotoBase64`; nunca `cuidadorId`,
`codigoVinculacion` ni `dispositivoVinculadoId`. Los campos opcionales vacÃ­os se
guardan como `null` (la foto tambiÃ©n se puede quitar). El telÃ©fono se escribe
sin espacios y conserva el `+` inicial si lo tiene. La validaciÃ³n vive en
`validacion_ficha_paciente.dart` y la comparten el alta y la ediciÃ³n.

**`codigoVinculacion` en detalle**

- Formato `MEDI-XXXXXX` sobre el alfabeto `'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'`
  (`vinculacion_service.dart:24`), sin `0/O` ni `1/I` para copiarlo a mano.
- Regex assertion en `test/widget_test.dart:171-174`:
  `^MEDI-[A-HJ-NP-Z2-9]{6}$`.
- `generarCodigo()` (`vinculacion_service.dart:37-44`) usa `Random.secure()`.
  **No** es un LCG hecho a mano.
- **Solo es Ãºnico por cuidador.** El chequeo de duplicados usa
  `buscarPacientePorCodigo(codigo, uid)` (`vinculacion_service.dart:55-73`), que
  filtra por el `cuidadorId` propio. Ahora el `create` de `vinculos` exige
  `!exists(...)` (`firestore.rules:88-92`), asÃ­ que un choque entre cuidadores ya
  no repunta el Ã­ndice: la creaciÃ³n del paciente falla y se revierte
  (`firestore_service.dart:141-152`). El botÃ³n "Generar cÃ³digo nuevo" sÃ­
  reintenta (`vinculacion_service.dart:87-99`).
- Se normaliza con `.trim().toUpperCase()` antes de consultar
  (`firestore_service.dart:793` y `vinculacion_service.dart:111`).
- **Vencimiento.** Cada vÃ­nculo nuevo guarda
  `expiraEn = ahora + duracionCodigoVinculacion` (72 h,
  `constants.dart:18`, `firestore_service.dart:142-145`). Los documentos viejos
  sin `expiraEn` se consideran vigentes (`estado_codigo_vinculacion.dart:10-15`).
  Un paciente no puede usar un cÃ³digo vencido salvo que ya sea el dispositivo
  vinculado (reingreso) (`firestore_service.dart:805-813`,
  `vinculacion_service.dart:115-116`).

**`dispositivoVinculadoId` â€” todos los valores posibles**

| Valor | Significado | QuiÃ©n lo escribe |
|---|---|---|
| `''` | **Libre**: el paciente puede vincularse | `crearPaciente` (`firestore_service.dart:134`) y `desvincularDispositivo` (`:912-931`) |
| `<uid anÃ³nimo>` | **Vinculado** a ese telÃ©fono | `vincularDispositivoPorCodigo` (`:789-852`) |
| `null` | Solo documentos creados **antes** del fix | nadie (legacy) |

> **Trampa de datos.** `estaLibre()` (reglas, lÃ­neas 20-22) acepta `null` **o**
> `''`. La vinculaciÃ³n actual ya **no** filtra pacientes por
> `dispositivoVinculadoId == ''`: resuelve el cÃ³digo en `vinculos`, hace un
> `update` directo y deja que la regla valide el documento. Por eso un documento
> legado con `null` tambiÃ©n se puede vincular. `crearPaciente` sigue escribiendo
> `''` explÃ­citamente (`firestore_service.dart:134`).

> **Nunca** escribas ahÃ­ el `disp-<micros>` de `LocalStore.getDispositivoId()`
> (`local_store.dart:25-33`): las reglas lo comparan contra `request.auth.uid`,
> asÃ­ que serÃ­a rechazado. Ese mÃ©todo ademÃ¡s estÃ¡ **muerto** (nadie lo llama).

### Referencias

| Campo | Apunta a |
|---|---|
| `cuidadorId` | `usuarios/{uid}` |
| â€” | `tratamientos.pacienteId` y `registrosToma.pacienteId` apuntan acÃ¡ |

### Reglas de seguridad (`firestore.rules`)

| OperaciÃ³n | CondiciÃ³n | LÃ­nea |
|---|---|---|
| read | `isAuthenticated()` **y** (uid == `cuidadorId` **o** uid == `dispositivoVinculadoId`) | 37-39 |
| create | `isAuthenticated()` **y** `cuidadorId == request.auth.uid` **y** `codigoVinculacion != null` **y** `nombre != null` | 40-43 |
| update | `isAuthenticated()` **y** (uid == `cuidadorId` **o** (el nuevo `dispositivoVinculadoId` == `request.auth.uid` **y** el doc estaba libre **y** solo cambia `dispositivoVinculadoId` **y** el vÃ­nculo de `codigoVinculacion` no estÃ¡ vencido)) | 44-54 |
| delete | `isAuthenticated()` **y** uid == `cuidadorId` | 55-56 |

O sea: el paciente (sesiÃ³n anÃ³nima) **no puede** crear ni borrar su propio
documento, y **no puede** desvincularse. Solo el cuidador dueÃ±o libera el
cÃ³digo, llamando a `desvincularDispositivo` (que escribe `''`). La rama de
lectura ya **no** incluye documentos libres: el paciente llega al documento por
el Ã­ndice `vinculos/{codigo}` y, tras el `update`, la lectura directa ya estÃ¡
autorizada por `dispositivoVinculadoId`. `estaLibre` (lÃ­neas 20-22) solo se usa
en la condiciÃ³n de `update`. La condiciÃ³n del paciente usa
`vinculoVigenteDelPaciente` (`firestore.rules:24-29`), que lee
`vinculos/{codigoVinculacion}` con `get()` y acepta `expiraEn` ausente o
posterior a `request.time`.

### CÃ³mo consultar â€” lo importante

La regla de `read` (37-39) es una **disyunciÃ³n de dos ramas**, y Firestore solo
autoriza una *query* si los filtros de la propia query pueden **demostrar** que
todo documento devuelto cumple la regla. Por eso los filtros "redundantes"
**no** se pueden sacar:

| MÃ©todo | Filtros | QuÃ© rama demuestra | Si sacÃ¡s el filtro |
|---|---|---|---|
| `streamPacientesDelCuidador` (`:71-79`) | `cuidadorId == uid` | rama 1 | pierde todos tus pacientes |
| `buscarPacientePorCodigo` (`:763-771`) | `codigoVinculacion ==` + `cuidadorId == uid` + `limit(1)` | rama 1 | **403** "Missing or insufficient permissions", incluso para pacientes propios |
| `streamPacientePorDispositivo` (`:81-90`, **muerto**) | `dispositivoVinculadoId ==` + `limit(1)` | rama 2 | â€” |
| `getPacienteVinculadoParaReingreso` (`:736-750`) | `dispositivoVinculadoId == uid` | rama 2 | **403**; no puede demostrar que el doc es del dispositivo |

- **Con demostrar una sola rama alcanza**; no hacen falta las dos.
- `getPaciente` (`:100-107`) y `streamPacienteDoc` (`:94-98`) usan `.doc(id)`:
  son accesos directos, la regla se evalÃºa sobre el documento, no hay filtro que
  agregar.
- `vincularDispositivoPorCodigo` (`:789-852`) **no** consulta pacientes por
  `dispositivoVinculadoId == ''`: lee `vinculos/{codigo}`, comprueba reingreso y
  vencimiento, hace el `update` directo y, si la escritura funciona, ya puede
  leer el documento porque el nuevo `dispositivoVinculadoId` es su propio UID.
- **No hace falta Ã­ndice compuesto**: solo hay igualdades y `limit`, sin
  `orderBy`.
- `vincularDispositivoAPaciente` (`:158-165`) estÃ¡ **muerto** y serÃ­a rechazado
  igual: quien llama no es el dueÃ±o y el token local no es `request.auth.uid`.

---

## `vinculos/{codigo}`

### ID del documento

= **el cÃ³digo de vinculaciÃ³n normalizado**: `trim().toUpperCase()`, formato
`MEDI-XXXXXX`. No es autogenerado. El Ã­ndice existe para que el dispositivo
anÃ³nimo pueda resolver un cÃ³digo sin poder leer todos los pacientes libres.
`crearPaciente` lo escribe con `.set()` despuÃ©s de crear el paciente
(`firestore_service.dart:142-145`), `reemplazarCodigoVinculacion` crea el nuevo
en la transacciÃ³n (`:897`) y `desvincularDispositivo` lo vuelve a escribir con
el cÃ³digo normalizado (`:924-927`).

### Campos

| Campo | Tipo | Â¿Null / vacÃ­o? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Nunca null | â†’ `pacientes/{id}` |
| `expiraEn` | `Timestamp` | Puede faltar en documentos viejos | Fecha en que el cÃ³digo deja de servir. Ausente = vigente por compatibilidad |

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |

### Reglas de seguridad (`firestore.rules`)

| OperaciÃ³n | CondiciÃ³n | LÃ­nea |
|---|---|---|
| get | `isAuthenticated()` | 87 |
| create | `isAuthenticated()` **y** `pacienteId != null` **y** `expiraEn is timestamp` **y** `!exists(vinculos/{codigo})` **y** `esCuidadorDelPaciente(pacienteId)` | 88-92 |
| update | `isAuthenticated()` **y** `pacienteId` no cambia **y** `esCuidadorDelPaciente(resource.data.pacienteId)` | 95-98 |
| delete | `isAuthenticated()` **y** `pacienteId != null` **y** `esCuidadorDelPaciente(pacienteId)` | 99-101 |

Cualquier usuario autenticado puede **obtener** un cÃ³digo por ID (`get`), porque
el paciente anÃ³nimo lo necesita para resolverlo. `allow get` **no** incluye
`list`: nadie puede listar la colecciÃ³n completa. El `create` no puede pisar un
documento existente (`!exists`), asÃ­ que un cÃ³digo ajeno no se puede repuntar.
El `update` solo permite reescribir el mismo `pacienteId` y exige ser el
cuidador del paciente al que ya apuntaba, lo que evita secuestrar el vÃ­nculo de
otro cuidador. El `delete` queda limitado al cuidador dueÃ±o.
`esCuidadorDelPaciente` estÃ¡ en las lÃ­neas 10-13.

### CÃ³mo consultar

| MÃ©todo | Filtros | Ãndice |
|---|---|---|
| `vincularDispositivoPorCodigo` (`firestore_service.dart:789-852`) | `.doc(codigoNormalizado).get()` | ninguno: acceso directo |
| `crearPaciente` (`:142-145`) | `.doc(codigo).set(...)` | ninguno |
| `reemplazarCodigoVinculacion` (`:854-910`) | transacciÃ³n con `.doc(nuevo).get()` y `.doc(viejo).get()` | ninguno: acceso directo |
| `desvincularDispositivo` (`:924-927`) | `.doc(codigo).set(...)` | ninguno |

### Generar un cÃ³digo nuevo

1. El botÃ³n solo aparece si `pacientes/{id}.dispositivoVinculadoId` estÃ¡ vacÃ­o
   (`detalle_paciente_screen.dart:942-956`). Si estÃ¡ vinculado, se explica que
   primero hay que desvincular.
2. El cuidador confirma el diÃ¡logo; `VinculacionService.regenerarCodigoVinculacion`
   genera un cÃ³digo y llama a `FirestoreService.reemplazarCodigoVinculacion`
   (`vinculacion_service.dart:87-99`).
3. La transacciÃ³n lee el paciente y el cÃ³digo candidato, rechaza si el paciente
   ya estÃ¡ vinculado o si el cÃ³digo existe, crea `vinculos/{nuevo}` con
   `expiraEn`, actualiza `pacientes/{id}.codigoVinculacion` y borra el vÃ­nculo
   viejo (`firestore_service.dart:854-910`).
4. La tarjeta muestra el vencimiento leyendo `vinculos/{codigo}` con un stream,
   permite copiar el cÃ³digo y muestra "CÃ³digo vencido" cuando corresponde
   (`detalle_paciente_screen.dart:797-1009`).

**CÃ³digo repetido entre cuidadores.** El chequeo de unicidad de
`generarCodigo` solo mira los pacientes del propio cuidador
(`vinculacion_service.dart:55-73`). Dos cuidadores pueden generar el mismo
cÃ³digo, pero el `create` de `vinculos` exige `!exists(...)`: el segundo
`crearPaciente` falla al escribir el vÃ­nculo y borra el paciente reciÃ©n creado
(`firestore_service.dart:141-152`). El botÃ³n "Generar cÃ³digo nuevo" sÃ­ reintenta
con otro cÃ³digo (`vinculacion_service.dart:87-99`). No hay unicidad global.

---

## `medicos/{uid}`

Perfil pÃºblico del doctor que ven sus pacientes vinculados. El id del
documento es el **UID de Firebase Auth** del cuidador, no un id autogenerado.

| Campo | Tipo | Regla |
|---|---|---|
| `nombre` | `String` | Obligatorio, mÃ¡x. 80 caracteres |
| `titulo` | `String` | Estudios, mÃ¡x. 120 caracteres |
| `especialidad` | `String` | MÃ¡x. 80 caracteres |
| `fotoBase64` | `String?` | Data URI JPEG, miniatura de 256 px y mÃ¡x. 60 KB |
| `actualizadoEn` | `Timestamp` | `FieldValue.serverTimestamp()` |

Modelo: `lib/models/medico.dart`. ValidaciÃ³n pura:
`lib/utils/validacion_perfil_medico.dart`. CompresiÃ³n:
`ImagenService.fotoPerfilABase64` (`lib/services/imagen_service.dart`).
Lectura del paciente: `FirestoreService.getMedico`, **un solo `get`** con
timeout de 8 s y caÃ­da a cachÃ©; si falla o no existe, la tarjeta no se muestra.

**Reglas** (`firestore.rules`, bloque `match /medicos/{uid}`):

- `get` para cualquier usuario autenticado; `list` explÃ­citamente denegado.
- `create`, `update` y `delete` solo del dueÃ±o (`request.auth.uid == uid`) con
  sesiÃ³n **no anÃ³nima**.
- `create`/`update` exigen exactamente las cinco claves, con los tipos y
  tamaÃ±os indicados y `actualizadoEn == request.time`.

**Riesgo:** cualquiera que conozca el uid puede leer ese perfil. El uid no es
adivinable y el documento solo contiene datos pensados para los pacientes.

**Alternativa descartada:** copiar el perfil en cada `pacientes/{id}`.
Requiere reescribir todos los pacientes al cambiar el perfil (mÃ¡s escrituras,
coste y posibilidad de datos desincronizados), ademÃ¡s de duplicar la foto.

Los pacientes ven el cambio la prÃ³xima vez que abren Horario o el detalle; no
hay push para este perfil.

## `tratamientos/{id}`

### ID del documento

= **autogenerado por Firestore**. `crearTratamiento` hace `.add(...)`
(`firestore_service.dart:205-207`).

`actualizarTratamiento` (`:216-220`) hace
`.doc(id).update(tratamiento.toMap())`, o sea un **reemplazo completo**: se
reescriben todos los campos. Por eso el editor conserva explÃ­citamente
`ultimoAvisoSinTomas` (`editar_tratamiento_screen.dart:291-293`).

### Campos

| Campo | Tipo | Â¿Null / vacÃ­o? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Nunca null | â†’ `pacientes/{id}`. **Es el ancla de autorizaciÃ³n** de toda la colecciÃ³n |
| `nombreMedicamento` | `String` | Default `''` al leer | Nombre, por ejemplo "LosartÃ¡n" |
| `fotoBase64` | `String?` | **Puede ser `null`** | Data URI `data:image/jpeg;base64,...` |
| `dosis` | `String` | Default `'1'` al leer | **Â¡Es texto, no un nÃºmero!** Se muestra como `"$dosis DOSIS"` |
| `horarios` | `List<Map>` | Default `[]` al leer | Cada elemento es `{hora: "HH:mm", dias: [1..7]}`; ver abajo la compatibilidad con el formato viejo `List<String>` |
| `frecuencia` | `String` | Default `''` al leer | Texto libre: `'Diaria'`, `'Cada 12 h'`, `'Cada 8 h'`, `'Semanal'`, `'Solo cuando sea necesario'`. **Decorativa** |
| `duracion` | `String?` | Opcional | Texto legible (`'7 dÃ­as'`, `'Continuo'`). No decide la finalizaciÃ³n |
| `fechaInicio` | `Timestamp?` (en Dart, `DateTime?`) | Opcional; **null** en documentos viejos | Fecha local **sin hora** desde la que cuenta el tratamiento |
| `duracionDias` | `int?` | Opcional; **null** = continuo o desconocido | DÃ­as de duraciÃ³n; junto con `fechaInicio` define la fecha de fin |
| `ultimoAvisoSinTomas` | `Timestamp?` (en Dart, `DateTime?`) | Opcional; **null** = sin aviso pendiente | Fecha local del Ãºltimo push de 5 dÃ­as sin tomas; evita repetirlo el mismo dÃ­a y se borra al romper la racha |
| `recetadoPorId` | `String?` | Opcional en documentos antiguos | UID del cuidador que recetÃ³. Si falta, se usa `paciente.cuidadorId` (`lib/utils/medico_tratamiento.dart`) |

Los campos estÃ¡n en `tratamiento.dart:56-67`, se leen en `fromMap`
(`:83-98`) y se escriben siempre en `toMap` (`:140-153`). `fechaInicio` y
`ultimoAvisoSinTomas` se normalizan a fecha local sin hora con `_parseFecha`
(`:100-112`); `duracionDias` se valida como entero positivo (`:114-117`).

**`fotoBase64`**

- La foto va **dentro del documento**, no a Firebase Storage. `ImagenService`
  la recorta a `maxDimension = 800` px y la comprime hasta `maxBytes = 280 * 1024`
  (`imagen_service.dart:12-13`) para no pasar el lÃ­mite de 1 MB por documento.
- `toMap()` siempre escribe la clave, asÃ­ que sin foto queda **guardada como
  `null`**, no ausente.
- Todos los consumidores la chequean con `!= null && !isEmpty`
  (`detalle_paciente_screen.dart:223`, `medicamentos_proximos_screen.dart:467`,
  `alarma_screen.dart:91`).
- Se muestra con `MemoryImage` / `Image.memory`
  (`detalle_paciente_screen.dart:225-226`, `medicamentos_proximos_screen.dart:484`,
  `alarma_screen.dart:367`). **Nunca** `NetworkImage` / `Image.network`.

**`fechaInicio`, `duracionDias` y `duracion`**

- `fechaInicio` y `duracionDias` son la fuente real de la vigencia. La fecha de
  fin es **inclusiva**: un tratamiento de 3 dÃ­as que empieza el lunes termina el
  miÃ©rcoles (`vigencia_tratamiento.dart:12-22`).
- `duracionDias == null` significa continuo **o** desconocido (documentos
  viejos): en ambos casos no se calcula fecha de fin y el tratamiento se
  considera vigente (`vigencia_tratamiento.dart:24-34`).
- `duracion` es solo el texto legible (`'7 dÃ­as'`, `'Continuo'`) que se muestra;
  no participa de ningÃºn cÃ¡lculo (`editar_tratamiento_screen.dart:286-290`).
- El editor solo permite elegir una fecha de inicio hasta hoy
  (`editar_tratamiento_screen.dart:144-158`).

**`ultimoAvisoSinTomas`**

- Solo lo escribe el **paciente** al enviar la alerta de 5 dÃ­as sin tomas:
  `FirestoreService.marcarAvisoSinTomas` guarda la fecha local sin hora
  (`firestore_service.dart:226-232`).
- Se borra con `FieldValue.delete()` cuando una toma confirmada rompe la racha
  (`firestore_service.dart:235-239`).
- Es el Ãºnico campo de `tratamientos` que el paciente puede actualizar (ver
  reglas abajo). El cuidador lo conserva al editar el tratamiento
  (`editar_tratamiento_screen.dart:291-293`).

**`frecuencia` es solo decorativa**

El dropdown de `editar_tratamiento_screen.dart:406-415` y `:458-465` ofrece
`Diaria`, `Cada 12 h`, `Cada 8 h`, `Semanal` y `Solo cuando sea necesario`; se
guarda y se muestra, pero
**ninguna lÃ³gica lo lee** para calcular dosis. La programaciÃ³n de alarmas y la
detecciÃ³n de tomas pendientes usan **solo `horarios`**
(`editar_tratamiento_screen.dart:220-282`,
`notificaciones_service.dart:601-620`). No construyas nada sobre `frecuencia`
sin revisarlo.

**`dosis` y `horarios`**

- `dosis` se guarda con `dosis.isEmpty ? '1' : dosis`
  (`editar_tratamiento_screen.dart:275`). No la pases por `int.parse` sin guarda.
- `horarios` es una lista de mapas `{hora, dias}` (`tratamiento.dart:11-36`).
  `fromMap` acepta el formato viejo `['HH:mm']` y lo expande a todos los dÃ­as
  (`tratamiento.dart:119-138`); una lista explÃ­cita de dÃ­as, aunque estÃ© vacÃ­a,
  se respeta.
- `hora` se parte con `split(':')` en varios lugares
  (`proxima_toma.dart:50`, `omitidas_service.dart:158`,
  `notificaciones_service.dart:338`). **MantenÃ© el formato `"HH:mm"`** o se
  rompe el agendado.

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |
| â€” | `registrosToma.tratamientoId` apunta acÃ¡ |

### Reglas de seguridad (`firestore.rules`)

| OperaciÃ³n | CondiciÃ³n | LÃ­nea |
|---|---|---|
| read | `esCuidadorDelPaciente(resource.data['pacienteId'])` **o** `esDispositivoVinculado(resource.data['pacienteId'])` | 50-51 |
| update | `esCuidadorDelPaciente(...)` **o** (`esDispositivoVinculado(...)` **y** `request.resource.data.diff(resource.data).affectedKeys().hasOnly(['ultimoAvisoSinTomas'])`) | 54-58 |
| create | `esCuidadorDelPaciente(request.resource.data['pacienteId'])` | 59 |
| delete | `esCuidadorDelPaciente(resource.data['pacienteId'])` | 60 |

- El **paciente** puede **leer** los tratamientos de su paciente, pero en
  `update` solo puede tocar `ultimoAvisoSinTomas`. No puede crear ni borrar
  tratamientos, ni cambiar `horarios`, `dosis`, `fechaInicio`, etc.
- Esa restricciÃ³n es exactamente la que necesitan `marcarAvisoSinTomas`
  (`firestore_service.dart:226-232`) y `limpiarAvisoSinTomas` (`:235-239`).
  Borrar el campo con `FieldValue.delete()` tambiÃ©n cuenta como una sola clave
  afectada.
- El **cuidador** conserva el CRUD completo.
- En `create` se lee `request.resource.data` porque **`resource` es `null`**.
  En el resto, `resource` es el doc actual.
- Las dos funciones helper (lÃ­neas 10-18) hacen un `get()` del documento
  `pacientes/{id}`, asÃ­ que el llamador **tambiÃ©n** tiene que poder leer ese
  paciente.

### CÃ³mo consultar

| MÃ©todo | Filtros | Ãndice |
|---|---|---|
| `streamTratamientosDePaciente` (`firestore_service.dart:180-189`) | `pacienteId ==` | no necesita |
| `detalle_paciente_screen.dart:185-186` | `pacienteId ==` (stream crudo, no el service) | no necesita |

- El `where('pacienteId', ...)` es **lo que hace resoluble** el `get()` que
  hacen los helpers. Sin Ã©l, la query no puede probarse contra la regla.
- No hace falta un `where` extra por `dispositivoVinculadoId`: los helpers
  hacen un `get()` por documento (evaluado por documento), no forman parte del
  conjunto de filtros de la query.
- Una sola igualdad, sin `orderBy` â†’ **no** hace falta Ã­ndice compuesto.

---

## `registrosToma/{id}`

### ID del documento

= **determinista por ranura** en confirmaciones finales (`tomÃ³`/`tardÃ³`) y en
olvidadas: `idDocumentoDeRanura(tratamientoId, horaProgramada)` deriva el id de
`hashEstable('omitida|...')` y se escribe con `.set()`. AsÃ­ confirmar y olvidar
compiten por el mismo documento y una segunda confirmaciÃ³n no puede crear otro.

Las posposiciones usan un **id autogenerado** (`.add(...)`): posponer no cierra
la ranura, y una confirmaciÃ³n posterior debe poder crear el documento final sin
actualizar el existente.

`confirmarToma` (`:287-295`) apunta a un doc existente con `.doc(id).update(...)`,
pero estÃ¡ **muerto**: nadie lo llama.

### Campos

| Campo | Tipo | Â¿Null / vacÃ­o? | Significado |
|---|---|---|---|
| `pacienteId` | `String` | Default `''` al leer | â†’ `pacientes/{id}`. **Ancla de autorizaciÃ³n** |
| `tratamientoId` | `String` | Default `''` al leer | â†’ `tratamientos/{id}` |
| `horaProgramada` | `Timestamp` (en Dart, `DateTime`) | Nunca null | Hora de la toma; se ordena y se filtra por rango |
| `horaConfirmacion` | `Timestamp?` (en Dart, `DateTime?`) | **Puede ser `null`** | Momento de confirmaciÃ³n; `null` si `estado` es `pendiente` u `olvidÃ³` (`registro_toma.dart:54-61`) |
| `estado` | `String` | Nunca null | Ver tabla abajo |

**`estado`: el miembro del enum y el string guardado NO coinciden**

El enum Dart es `EstadoToma`; lo que se persiste es `EstadoTomaExt.nombre`
(`registro_toma.dart:12-26`):

| Miembro del enum | String en Firestore |
|---|---|
| `pendiente` | `pendiente` |
| `tomada` | **`tomÃ³`** |
| `tardia` | **`tardÃ³`** |
| `olvidada` | **`olvidÃ³`** |
| `pospuesta` | `pospuesta` |

`EstadoTomaExt.fromNombre` (`:28-41`) mapea cualquier string desconocido a
`pendiente` (rama `default`).

`detalle_paciente_screen.dart:975-981` **hardcodea** los literales `'tomÃ³'`,
`'tardÃ³'`, `'olvidÃ³'`: actualizalo si agregÃ¡s un estado.

**QuÃ© escribe realmente el cÃ³digo hoy**

Hoy se producen los cuatro estados no pendientes:

- `tomÃ³` o `tardÃ³` al confirmar en la pantalla de alarma
  (`alarma_screen.dart:147-170`); `tardÃ³` si `now - horaProgramada > 15 min`.
- `pospuesta` al pulsar "Recordar" (`alarma_screen.dart:191-203`).
- `olvidÃ³` desde la reconciliaciÃ³n de tomas perdidas
  (`omitidas_service.dart:330-335`), con `horaConfirmacion = null`.

`pendiente` sigue sin escribirse nunca (es el default del modelo). Los
contadores "Tomadas/TardÃ­as/Olvidadas" de `detalle_paciente_screen.dart:975-981`
comparan los literales `'tomÃ³'`, `'tardÃ³'` y `'olvidÃ³'` a mano.

**No hay un doc por dosis en el camino normal**

"YA" y "Recordar" siempre crean un `.add()` nuevo, nunca actualizan un
pendiente. La excepciÃ³n es la toma olvidada, que usa un id determinista para ser
idempotente. `_yaConfirmada` (`medicamentos_proximos_screen.dart:240-252`)
trata `pospuesta` como *no confirmada*, asÃ­ que una dosis pospuesta vuelve a
sonar. No armes queries que asuman unicidad por
(`tratamientoId`, `horaProgramada`) salvo para las olvidadas.

### Referencias

| Campo | Apunta a |
|---|---|
| `pacienteId` | `pacientes/{id}` |
| `tratamientoId` | `tratamientos/{id}` |

### Reglas de seguridad (`firestore.rules`)

| OperaciÃ³n | CondiciÃ³n | LÃ­nea |
|---|---|---|
| read | `esCuidadorDelPaciente(resource.data['pacienteId'])` **o** `esDispositivoVinculado(...)` | 64-65 |
| create | `esCuidadorDelPaciente(request.resource.data['pacienteId'])` **o** `esDispositivoVinculado(...)` | 69-70 |
| update, delete | solo `esCuidadorDelPaciente(resource.data['pacienteId'])` | 71 |

El paciente **crea** sus propios registros al confirmar o posponer, y la
reconciliaciÃ³n escribe las olvidadas; **no puede modificar ni borrar** los
existentes. El cuidador los **lee** en tiempo real para el dashboard y conserva
la correcciÃ³n administrativa.

### CÃ³mo consultar â€” acÃ¡ sÃ­ hacen falta Ã­ndices compuestos

`firestore.indexes.json` ya contiene las definiciones de los compuestos que usa
el cÃ³digo (lÃ­neas 2-67), pero en este proyecto los Ã­ndices de producciÃ³n se han
gestionado desde la consola de Firebase. Un `FAILED_PRECONDITION` /
"requires an index" se resuelve creando el Ã­ndice **en la consola**; no asumas
que desplegar el archivo del repo lo crea.

| MÃ©todo | Filtros | Ãndice compuesto necesario |
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
  conservador: Firestore admite hasta 30 valores en un `in`, y el cÃ³digo usa
  10.
- El filtro por `tratamientoId` de `streamTomasPendientesHoy` **no** lo pide la
  regla (las reglas solo se anclan en `pacienteId`): es un requisito **de
  Ã­ndice**, porque ensancha el compuesto. El rango va sobre el **Ãºltimo**
  campo, en intervalo semiabierto `[hoy, maÃ±ana)`.
- El `where('pacienteId', ...)` sigue siendo **obligatorio** por la misma razÃ³n
  que en `tratamientos`: es lo que hace resoluble el `get()` de los helpers.

---

## EliminaciÃ³n de un paciente

La implementa `FirestoreService.eliminarPaciente` y se lanza desde el menÃº de
tres puntos del detalle, tras escribir el nombre exacto del paciente.

Datos asociados a un `pacienteId` (no hay subcolecciones):

| ColecciÃ³n | CÃ³mo se identifica | Archivo |
|---|---|---|
| `pacientes/{id}` | id del documento | `firestore_service.dart` (`_pacientesCollection`) |
| `tratamientos/{id}` | campo `pacienteId` | `firestore_service.dart` (`_tratamientosCollection`) |
| `registrosToma/{id}` | campo `pacienteId` (historial y tomas olvidadas) | `firestore_service.dart` (`_registrosCollection`) |
| `vinculos/{codigo}` | campo `pacienteId` dentro del documento del cÃ³digo | `firestore_service.dart` (`_vinculosCollection`) |

No existe una colecciÃ³n `alertas`: la alerta de 5 dÃ­as es el campo
`tratamientos.ultimoAvisoSinTomas` y las tomas olvidadas viven en
`registrosToma` con estado `olvidÃ³`. `usuarios` y `medicos` son del doctor, no
del paciente, y no se tocan.

Orden exacto:

1. Lee y guarda en memoria `dispositivoFcmToken` y `dispositivoVinculadoId`.
2. Borrar `tratamientos` y `registrosToma` cuyo `pacienteId` coincida, en
   lotes de **mÃ¡ximo 400 operaciones** (`partirEnLotes`).
3. Borrar `vinculos/{codigoVinculacion}` si existe.
4. Borrar `pacientes/{id}` **al final**, porque las reglas de los hijos
   consultan `pacientes/{id}` para autorizar al cuidador.
5. Solo si todo terminÃ³ con Ã©xito y habÃ­a dispositivo vinculado con token,
   `PushService.notificarSincronizacionConToken` con el token guardado
   (best-effort; un fallo no revierte ni hace fallar el borrado).

Si falla un paso intermedio, el documento del paciente sigue existiendo y la
operaciÃ³n se puede repetir: las consultas solo devuelven los hijos que aÃºn
quedan. En el telÃ©fono del paciente, la desapariciÃ³n del documento (o un
`permission-denied`) dispara `LimpiezaPacienteService`: cancela notificaciones,
limpia `LocalStore` y la vinculaciÃ³n recordada, cierra la sesiÃ³n anÃ³nima y deja
un mensaje para la pantalla de selecciÃ³n de rol.


---

## Compatibilidad Android

- `minSdk = 24` (Android 7.0), `targetSdk = 36` (Android 16), `compileSdk = 36`.
- Permisos declarados: `INTERNET`, `VIBRATE`, `WRITE_SETTINGS` (especial), `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `RECEIVE_BOOT_COMPLETED`.
- Receivers declarados: `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`.

Matriz de versiones (probadas / no probadas):

| Android | API | Estado | Notas |
|---|---:|---|---|
| 7.0 | 24 | No probado en dispositivo, soportado por minSdk | Sin alarmas exactas ni pantalla completa; notificaciones sin permiso runtime |
| 8.0-8.1 | 26-27 | No probado | Canales de notificacion obligatorios |
| 9 | 28 | No probado | Sin alarmas exactas ni pantalla completa |
| 10 | 29 | No probado | Sin alarmas exactas ni pantalla completa |
| 11 | 30 | No probado | Visibilidad de paquetes; permiso de alarmas exactas aun no existe |
| 12-12L | 31-32 | No probado | Alarmas exactas requieren permiso |
| 13 | 33 | No probado | `POST_NOTIFICATIONS` runtime |
| 14 | 34 | No probado | Pantalla completa requiere permiso |
| 15 | 35 | No probado | Cambios de segundo plano y alarmas |
| 16 | 36 | Objetivo de compilacion | Target actual |\n| (por confirmar) | (por confirmar) | Probado en Samsung Galaxy A36 | Alarma funcionó |

## Limitaciones conocidas

- iOS no esta soportado en esta version: maximo 64 notificaciones locales programadas, sin alarma a pantalla completa ni arranque en segundo plano, y FCM requiere cuenta de Apple Developer.
- Fabricantes con ahorro agresivo de batería (Xiaomi, Huawei, Oppo, Realme, Vivo, Samsung) pueden retrasar o bloquear alarmas; se incluye guia por fabricante.
- La credencial de FCM viaja dentro del APK y es extraible; la mitigacion real es un servidor intermediario, no mover la clave.
- Las reglas de Firestore y los flujos dependientes de Firebase no tienen cobertura automatizada.
---

## Notificaciones locales

Los canales se crean en `NotificacionesService._crearCanales`
(`notificaciones_service.dart:218-274`) y sus ids estÃ¡n en `:50-54`. Los ids de
las notificaciones programadas son **deterministas** para poder cancelarlas sin
guardar nada en Firestore.

| Tipo | Id / rango | Canal | CuÃ¡ndo |
|---|---|---|---|
| Alarma principal | `idDeAlarma` = `hashEstable("<tratamientoId>|<hora>|<dÃ­a>")`, positivo en `[1, 0x7FFFFFFF]` (`:387-390`) | `alarmas_medicamentos` | Semanal, en la hora exacta; abre pantalla completa |
| Aviso previo | `[-0x0FFFFFFF, -1]` (`:409-410`, `:423-425`) | `avisos_previos` | Semanal, 5 min antes |
| FelicitaciÃ³n | `[-0x1FFFFFFF, -0x10000000]` (`:411-412`, `:428-434`) | `felicitaciones` | Inmediata al confirmar; no se programa |
| Recordatorio tardÃ­o semanal | `[-0x27FFFFFF, -0x20000000]` (`:413-414`, `:437-447`) | `recordatorios_tardios` | Semanal, 15 min despuÃ©s de la toma |
| Recordatorio tardÃ­o puntual | `[-0x2FFFFFFF, -0x28000000]` (`:415-416`, `:450-455`) | `recordatorios_tardios` | Una sola vez, al posponer |
| Aviso local del cuidador | Positivo sin subrango reservado: `millisecondsSinceEpoch & 0x7FFFFFFF` | `alertas_cuidador` | Solo tomas olvidadas, agrupadas, con la app visible. Las confirmaciones no notifican |

`hashEstable` es un polinomio de 31 bits con `0` reservado
(`hash_estable.dart:18-23`). El `0` nunca se usa como id. La alarma principal
usa ids positivos; los cuatro tipos nuevos usan subrangos negativos para no
chocar con ella (`notificaciones_service.dart:392-416`).

## Push FCM: la Ãºnica salida externa

El **Ãºnico** envÃ­o FCM que queda es la alerta de **5 dÃ­as sin tomas**:

- CÃ¡lculo puro: `AlertaSinTomasService.hayAlerta` (`alerta_sin_tomas_service.dart:22-40`)
  exige tratamiento vigente, `fechaInicio` conocido y que los Ãºltimos **5 dÃ­as
  programados** anteriores a hoy no tengan ninguna confirmaciÃ³n. Se saltan los
  dÃ­as sin toma programada; `pospuesta` no cuenta y `olvidÃ³` tampoco
  (`:111-120`).
- Disparo: `OmitidasService.reconciliar` evalÃºa la alerta despuÃ©s de escribir
  las tomas olvidadas (`omitidas_service.dart:358-366`) y llama a
  `_evaluarAlertasSinTomas` (`:398-463`).
- Antes de enviar, escribe `ultimoAvisoSinTomas` para que dos reconciliaciones
  solapadas no dupliquen el push (`omitidas_service.dart:442-452`). Si el
  tratamiento sale de la alerta (una toma confirmada), borra el campo
  (`:413-430`).
- EnvÃ­o: `PushService.notificarAlertaSinTomas` (`push_service.dart:171-231`)
  lee `pacientes/{id}.cuidadorFcmToken` (`:183-185`), firma un JWT con la cuenta
  de servicio y hace `POST .../messages:send` (`:190-219`). El cuerpo lleva
  nombre del paciente y del medicamento (`:199-205`) y el canal
  `alertas_cuidador` (`:206-214`).
- **No hay otro camino FCM.** No existe `notificarConfirmacion` ni ningÃºn otro
  `messages:send`; el dashboard solo muestra el resumen local de tomas
  olvidadas mientras la app estÃ¡ visible. Las confirmaciones no notifican.

### SincronizaciÃ³n del paciente en segundo plano

Cuando el cuidador crea, edita, borra o finaliza un tratamiento, la app envÃ­a
un push de **solo datos** al telÃ©fono del paciente:

- Enviador: `PushService.notificarSincronizacionAlPaciente`
  (`push_service.dart`), con `tipo: sync` y el `pacienteId`. TambiÃ©n existe
  `notificarSincronizacionConToken`, usada tras borrar un paciente con el token
  guardado en memoria. **No** lleva nombre
  del medicamento, dosis ni horarios; el paciente relee todo de Firestore. La
  prioridad Android es `high` y el TTL es de 3600 s.
- AgrupaciÃ³n: `SincronizacionPacienteService.programarEnvio` acumula cambios
  durante 10 s (`debounceSincronizacionPaciente`) para no enviar un push por
  cada ediciÃ³n.
- RecepciÃ³n con la app cerrada: `manejarMensajeSincronizacionFondo`
  (`main.dart`) es la funciÃ³n de nivel superior registrada con
  `onBackgroundMessage`. Inicializa Firebase, la zona horaria con
  `flutter_timezone`, registra el plugin de notificaciones y llama a
  `SincronizacionPacienteService.procesarMensaje`, que valida la vinculaciÃ³n
  local, lee los tratamientos del servidor (timeout de 8 s y luego cachÃ©),
  rearma la ventana de alarmas y actualiza `estadoDispositivo` respetando el
  throttle de 30 minutos.
- Con la app abierta: `FirebaseMessaging.onMessage` ejecuta el mismo rearme de
  inmediato (`iniciarEscuchaAppAbierta`).
- Seguridad: se ignora cualquier mensaje cuyo `pacienteId` no coincida con la
  vinculaciÃ³n local o cuyo UID no sea el `dispositivoVinculadoId`. El mensaje
  no autoriza nada por sÃ­ mismo.

**LimitaciÃ³n conocida:** si el usuario fuerza la detenciÃ³n de la app o el
fabricante bloquea el arranque en segundo plano, el mensaje no se procesa hasta
que el paciente abra la app. El cuidador verÃ¡ el estado en la tarjeta
â€œCelular del pacienteâ€ (`detalle_paciente_screen.dart`).
- Respaldo en la app del cuidador: `_AvisoSinTomas` recalcula lo mismo al abrir
  el detalle del paciente y pinta una tarjeta, **sin enviar FCM**
  (`detalle_paciente_screen.dart:373-484`).

âš ï¸ **Seguridad:** la credencial de la cuenta de servicio viaja dentro del APK
(`push_service.dart:32`, `assets/secrets/fcm_service_account.json`). Es
extraÃ­ble; el rol debe limitarse a `cloudmessaging.messages.create`. La soluciÃ³n
real serÃ­a un proxy/servidor, no mover el archivo.

---

## Diagrama de relaciones

```
                        Firebase Auth
                              â”‚
              uid            â”‚            uid anÃ³nimo
              (credenciales) â”‚            (signInAnonymously)
                              â–¼            â”‚
                    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
                    â”‚  usuarios/{uid}â”‚   â”‚  â† doc = UID de Auth, no autogenerado
                    â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
                    â”‚ uid      Str   â”‚   â”‚
                    â”‚ nombre    Str  â”‚   â”‚
                    â”‚ correo    Str  â”‚   â”‚
                    â””â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
                            â”‚            â”‚
                 cuidadorId â”‚            â”‚
                            â–¼            â”‚
        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
        â”‚            pacientes/{id}             â”‚  â† id autogenerado por .add()
        â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
        â”‚ nombre             String             â”‚
        â”‚ cuidadorId         String  â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â–º usuarios/{uid}
        â”‚ codigoVinculacion  String  MEDI-XXXXXXâ”‚
        â”‚ dispositivoVinculadoId String         â”‚â—„â”€â”€â”˜ '' = libre
        â”‚ cuidadorFcmToken   String?            â”‚
        â””â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”˜
             â”‚                         â”‚
   pacienteIdâ”‚                         â”‚pacienteId
             â–¼                         â–¼
   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
   â”‚ tratamientos/{id}    â”‚  â”‚       registrosToma/{id}     â”‚
   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤  â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
   â”‚ pacienteId      Str  â”‚  â”‚ pacienteId      Str  â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â–º pacientes/{id}
   â”‚ nombreMedicamento    â”‚  â”‚ tratamientoId    Str  â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â–º tratamientos/{id}
   â”‚ fotoBase64   String?  â”‚  â”‚ horaProgramada  Timestamp    â”‚
   â”‚ dosis         Str    â”‚  â”‚ horaConfirmacion Timestamp?  â”‚
   â”‚ horarios   List<Map> â”‚  â”‚ estado          String       â”‚
   â”‚ frecuencia    Str    â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
   â”‚ fechaInicio DateTime?â”‚
   â”‚ duracionDias Int?    â”‚
   â”‚ ultimoAvisoSinTomas  â”‚
   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

   vinculos/{codigo} â”€â”€ pacienteId â”€â”€â–º pacientes/{id}
```

Las flechas son punteros unidireccionales: el documento hijo lleva el ID del
padre. No hay subcolecciones anidadas ni documentos de contraparte. El Ã­ndice
`vinculos/{codigo}` apunta al paciente y es la puerta de entrada del dispositivo
anÃ³nimo.

## Puntos de autorizaciÃ³n, de un vistazo

- `pacientes` es el **Ãºnico** lugar donde vive la identidad de los dos roles.
  Todo lo demÃ¡s se autoriza preguntando, mediante un `get()` al `pacientes` que
  corresponde, quiÃ©n es el `cuidadorId` y quiÃ©n es el `dispositivoVinculadoId`.
- Las funciones helper **deben** quedar dentro de
  `match /databases/{database}/documents` (lÃ­neas 26-112): fuera de ese bloque
  pierden el scope de `get()` y `$(database)`, y las reglas fallan en runtime.
- No hay Cloud Functions que validen nada: si una regla no lo permite, el
  cliente simplemente recibe `permission-denied`. Por eso cada query replica
  la condiciÃ³n de la regla en sus propios `where`.

