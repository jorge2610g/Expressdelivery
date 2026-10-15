# ORDEN 012 — Plan de APK QA de rendimiento (sin compilar)

- Repositorio: `jorge2610g/Expressdelivery`.
- Referencia de código revisada: PR #250, commit `ed4f1281` (rama `perf/map-continuity-offline-20261015`, borrador).
- Base de esta propuesta: `origin/main` = `95e22e27`. Esta rama no contiene cambios de PR #250.
- **Estado: no se ha generado ninguna APK ni AAB. No se ha creado ningún Release. No se ha fusionado nada en `main`. No se han ejecutado migraciones ni cobros.**

## 1. Resultado de la revisión del flujo actual

El flujo de compilación Android del repositorio (`.github/workflows/build-android.yml`) no puede compilar el commit `ed4f1281` desde su rama. Hay tres bloqueos verificados en el código:

### Bloqueo A — Guardia de trazabilidad frente a `main`

El paso «Guard Production traceability against current mobile source» aplica a los tipos `candidate-apk+aab`, `single-app-candidate-apk+aab` y `apk+aab`. Compara el SHA del candidato con `origin/main` sobre `lib`, `android`, `assets`, `pubspec.yaml`, `pubspec.lock` y el script de marca:

- Hoy `ed4f1281` difiere de `main` (`95e22e27`) en `lib/` (PR #250 añade cambios de mapa, caché y conexión).
- La guardia aborta cualquier diferencia, incluso cuando el candidato es posterior a `main`.
- Por tanto, el único candidato que pasa la guardia es un SHA idéntico a `main` en esas rutas.

**No se debe relajar esta guardia**: protege la trazabilidad de producción.

### Bloqueo B — Cada compilación publica un GitHub Release

Todas las ramas del paso «publicar» ejecutan `gh release create` con el APK, el AAB y el JSON de identidad. El tipo `candidate` marca la nota «NO publicar en Play», pero **sigue siendo un Release del repositorio**. Esto contradice la orden de «no crear un Release público». Antes de cualquier compilación de QA hay que cambiar el destino (sin Release, o Release en borrador/privado con acceso restringido). Eso es un cambio de flujo y requiere autorización.

### Bloqueo C — Tipo de artefacto QA no permitido

La migración `20261014224000_enforce_official_android_build_only.sql` rechaza `preview-apk` y `preview-apk+aab`. El tipo `build_jobs.artifact_type` solo admite tipos oficiales. Un tipo QA aislado requiere una migración nueva y revisada. **No se ha creado ni ejecutado.**

### Lo que no bloquea

- Versión: `pubspec.yaml` = `1.6.2+140`. El trabajo exige que `version_name` y `build_number` del job coincidan con el pubspec. Es posible sin cambiar versión.
- Firma: el workflow usa el keystore de subida oficial desde el servicio de firma. Eso debe mantenerse; no se debe usar firma de depuración para una APK que se presente como oficial.
- Identidad: `com.express.usuario1`, `lib/mobile_main.dart`. Correcto.

## 2. Requisitos para iniciar una compilación controlada

Solo cuando el propietario diga **«genera APK»** y elija una de estas rutas:

| Ruta | Qué implica | Autorización necesaria |
|---|---|---|
| **A. Fusionar PR #250 en `main` y compilar desde `main`** | La guardia pasa porque el candidato coincide con `main`. Compilación oficial con firma. | Revisión y fusión de PR #250 por el propietario. |
| **B. Tipo QA aislado** (`qa-perf-apk`) | Migración que añade el tipo, cambio de workflow que no crea Release público, guardia que se aplica solo a tipos de producción. | Revisión de seguridad, migración en Supabase, PR de workflow. Ninguna se ejecuta aquí. |
| **C. Compilación local** | No procede: sin keystore oficial en este entorno y fuera del flujo auditado. | No se recomienda. |

Requisitos comunes antes de cualquier compilación:

1. **Aprobación del propietario** con la frase exacta del workflow: `AUTORIZO APK QA`.
2. **Job de compilación** creado y aprobado por el propietario con `job_id` que coincide con el SHA elegido.
3. **Versión** del job igual a `pubspec.yaml` (`1.6.2` / `140` hoy).
4. **Sin Release público**: el destino de publicación debe cambiarse antes (Bloqueo B).
5. **Pruebas verdes en el SHA** (CI Flutter, análisis, Web).
6. **Cuentas de prueba** aisladas (ver §4). Nunca usar cuentas o datos de Producción Taxi.

## 3. Alternativa QA aislada propuesta (en borrador, sin aplicar)

Esta PR no modifica código de la app ni el workflow. Documenta la propuesta:

- Tipo `qa-perf-apk`, paquete `com.express.usuario1` (sin sufijo, según la regla del propietario), firma oficial.
- Publicación de artefactos como **artefacto de Actions con retención corta** en lugar de Release, o Release en borrador accesible solo al propietario.
- Guardia de trazabilidad activa para `candidate-apk+aab`, `single-app-candidate-apk+aab` y `apk+aab`; no se aplica a `qa-perf-apk`, que nunca se publica en Play.
- Migración: `alter table build_jobs ... check (artifact_type in (...))` incluyendo `qa-perf-apk`. **Requiere revisión de seguridad y autorización.**

## 4. Plan de pruebas (sin cobros reales)

Cuentas: dos cuentas de prueba en un entorno de prueba aislado (pasajero **A** y conductor **B**), más una segunda cuenta de pasajero **C** para el cambio de sesión. Ninguna cuenta de Producción. Sin pagos ni cobros reales: la billetera y las suscripciones quedan fuera.

Referencia del video del propietario: 89,7 s. Tiempos iniciales de comparación (no se publica el video en el repositorio):

| Escena | Tiempo | Qué comprobar |
|---|---|---|
| Inicio | 00:01–00:07 | Primera pantalla útil; sin datos de otra cuenta; caché correcta |
| Selección de ruta | 00:17–00:27 | Ruta visible sin parpadeo; sin duplicados |
| Mapa oscuro | 00:54–01:11 | Cambio de tema sin hueco en el mapa |
| Finalización | 01:20–01:25 | Estado final consistente; sin confirmación sin respuesta del servidor |

### Casos

| # | Caso | Pasos | Criterio de aceptación |
|---|---|---|---|
| 1 | Inicio en frío | Cerrar app, abrir, medir hasta primer render | Tiempo anotado; sin datos de otra cuenta |
| 2 | Dos cuentas, seguimiento | A pide viaje; B acepta; seguir estados hasta fin | Mapa visible en cada estado; estado coincide con servidor |
| 3 | Zoom y desplazamiento | Zoom in/out y arrastre en fase de viaje | Teselas no desaparecen; no hay hueco |
| 4 | Cambio de tema | Claro → oscuro → claro durante seguimiento | Mapa no se desmonta |
| 5 | Modo avión | Activar durante viaje | «Sin conexión · datos hace X»; acciones críticas bloqueadas; mapa anterior visible |
| 6 | Reconexión | Desactivar modo avión | «Reconectando» → en línea; estado releído del servidor |
| 7 | Cambio de sesión | Cerrar sesión A, entrar C | Sin ubicación, rutas ni estado de A |
| 8 | Continuidad de proveedor | Cambiar proveedor de teselas si la cuota lo permite | Atribución coincide con lo visible |
| 9 | Restauración | Matar proceso con sesión iniciada y reabrir | Caché de la cuenta activa; sin mezcla |

### Registro por prueba

Fecha, SHA, cuenta usada (identificador de prueba, sin datos personales), resultado, tiempo en el video de referencia y captura o grabación local. Ningún secreto ni token en el informe.

## 5. Riesgos y limitaciones

- No se ha compilado ni probado en dispositivo en este entorno.
- Los tiempos del video son referencia inicial; la comparación final la hace el propietario.
- Discrepancia detectada: `docs/ANDROID_OFFICIAL_NEXT_CANDIDATE_READINESS_20261014.md` menciona commits como «en main» (`ffd4261`, `836a489`, `7832ac8`). Se verificó que sí son ancestros de `origin/main`. Otros puntos del mismo documento (por ejemplo, la consulta a ZEGO) no se han verificado aquí.
- Bloqueos externos del propio documento de preparación siguen abiertos: `ZEGO_RESOURCE_ID` no configurado y llamadas Android sin certificar.

## 6. Pendientes que requieren al propietario

1. Elegir ruta A o B (§2).
2. Autorizar cambio del destino de publicación para que no sea un Release público.
3. Si B: autorizar la migración del tipo `qa-perf-apk` y el cambio de workflow.
4. Confirmar las cuentas de prueba y el entorno aislado.
5. Decir «genera APK» solo cuando todo lo anterior esté listo.

## 7. Restricciones respetadas

- Sin APK, sin AAB, sin Release, sin fusión, sin despliegue, sin migraciones.
- Sin cambios en Producción, en la guardia de trazabilidad ni en la firma.
- Sin cobros ni pagos reales; billetera pendiente de autorización de idempotencia.
- No se publica el video del propietario en el repositorio.
