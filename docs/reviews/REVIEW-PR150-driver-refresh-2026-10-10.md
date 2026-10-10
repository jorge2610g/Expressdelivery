# Revisión PR #150 — perf: scope and throttle driver refresh load

Revisor: Claude (arquitecto/revisor). Programadora: ChatGPT. Spec: `docs/specs/SPEC-2026-10-10-driver-refresh-load.md`.
Commit revisado: `f99dad02be87842a0464339f3f7cdedc43e7951b` (rama `chatgpt/driver-refresh-throttle`).

## VEREDICTO: CAMBIOS REQUERIDOS (no aprobado)
Buena base: el enfoque es correcto y la entrega fue honesta (no inventó mediciones,
marcó A y C como pendientes). Pero hay **2 fallos bloqueantes** que pueden mostrar
al conductor un estado desactualizado en momentos críticos (viaje cancelado/asignado).

## Lo que verifiqué por mi cuenta
| Verificación | Resultado |
|---|---|
| `flutter analyze lib` en la rama (Flutter 3.47.5, igual que CI) | 0 errores ✅ |
| `flutter test` | 64/64 ✅ (coincide con lo reportado) |
| Rama de validación `chatgpt/driver-refresh-throttle-ci`: blobs de los 3 archivos | idénticos a la rama del PR ✅ |
| Referencias a `_refreshDriverHome` | 0 (antes 18) ✅ |
| Alcance: solo 5 archivos (Dart + 1 helper + 1 test + 2 docs); sin SQL/RLS/funciones | ✅ |
| Servidor (`available_ride_requests_for_driver`): un conductor solo ve `r.zone_id = su zona` | el filtro por `zone_id` es **correcto** ✅ |
| `ride_requests`: 207 filas, 0 sin `zone_id`, 0 sin `channel`; ambas tablas en publicación Realtime | ✅ |
| Replica identity `default` (DELETE sin zona/canal) | el fail-closed está bien; lo cubre el timer ✅ |
| PR #150 muestra 0 checks (CI solo corre contra `main`) | aceptable: la evidencia vive en la rama `-ci` |

## Criterios de la spec
| Criterio | Estado |
|---|---|
| A (≤5 llamadas/60 s idle) | PENDIENTE-MANUAL (medición en Preview) |
| B (otra zona no dispara carga) | PASS en código y test unitario; falta ver en Preview |
| C (oferta ≤2 s) | PENDIENTE-MANUAL — **obligatorio antes de aprobar** |
| D (analyze/test) | PASS (verificado por mí) |
| E (test del throttle) | PASS, pero el test valida un diseño con el defecto B1 |

## Hallazgos BLOQUEANTES

### B1 — El throttle descarta eventos en vez de agruparlos (puede dejar el panel desactualizado hasta ~22 s)
- Dónde: `_requestDriverRefresh()` en `lib/video_style_home.dart` (≈línea 6777) y `DriverRefreshThrottle.accept` en `lib/driver_refresh_control.dart`.
- Qué pasa: si llega un disparo dentro de los 2 s posteriores a un refresco completo, `accept()` devuelve `false` y la función **retorna sin hacer nada ni programar nada**. La spec pedía "agrupar disparos", es decir, que no se pierdan.
- Disparadores afectados (todos usan `_requestDriverRefresh`): push `ride_assigned`, `trip_status`, `passenger_on_way`, `trip_cancelled` (≈6711); `_clearDriverOfferWait(refresh:true)` (≈6625); tras enviar oferta (≈7526, 7564, 7611); tras reclamar entrega (≈7624); tras completar viaje (≈7769); cambio de `revision` (≈6766).
- Escenario real: el timer de 12 s termina un refresco en t. En t+1 s el pasajero cancela el viaje y llega el push `trip_cancelled`. El refresco se descarta. El timer siguiente omite la carga porque "hubo uno hace <12 s". El conductor ve el viaje cancelado como activo hasta ~t+22 s. **Antes de este cambio ese refresco se ejecutaba de inmediato** (solo se bloqueaba si había otro en curso): es una regresión en una transición crítica.
- También: si el disparo llega mientras hay un refresco en curso, tampoco se repite (el estado que ese refresco leyó puede ser anterior al evento).

### B2 — El refresco ligero puede sobrescribir un estado más nuevo (pérdida de actualización)
- Dónde: `_refreshDriverAvailabilityOnly()` (≈6850–6930).
- Qué pasa: captura `currentData = cachedData` al inicio, espera 2 llamadas de red y luego guarda `cachedData = next` construido con `currentData` **viejo** (viaje activo, perfil, contraparte). Solo se protege contra un refresco completo *ya en curso al inicio*; no contra uno que **empiece después** (`_requestDriverRefresh` no mira `driverAvailabilityRefreshInFlight`).
- Escenario real: llega una solicitud nueva (Realtime) → inicia la lectura ligera con "sin viaje activo". En ese momento el conductor es asignado a un viaje y llega el push `ride_assigned` → inicia el refresco completo, que termina antes y publica `activeTrip`. La lectura ligera termina después y publica el estado viejo con `activeTrip = null` y `driverFuture = Future.value(next)`: la pantalla vuelve a mostrar solicitudes disponibles y oculta el viaje activo hasta el siguiente refresco completo.

## No bloqueantes
- N1: la PR #151 temporal y la rama `-ci` deben cerrarse/borrarse al terminar. Como B1/B2 cambian código, **la evidencia de CI debe regenerarse** sobre el commit final (nuevo id de run y nuevos hashes).
- N2: el PR #150 apunta a `claude/express-admin-audit-cp07ml`. Orden de fusión: primero #148, luego reapuntar #150 a `main`.
- N3: el refresco ligero no actualiza `profile` (p. ej. un admin que deja offline al conductor). Aceptable: lo cubre el refresco completo del timer. Documentarlo en el código.
- N4: los tests cubren solo funciones puras; los dos defectos viven en la coordinación. Ver pruebas exigidas.

## Instrucciones de corrección (sin código; implementa la IA programadora)

### Para B1
1. Sustituir el throttle "leading-edge que descarta" por un **coordinador con ejecución final (trailing)**: si llega un disparo dentro de la ventana de 2 s, o mientras hay un refresco completo en curso, se **recuerda** y se ejecuta **exactamente una vez** al terminar la ventana/refresco. Nunca se descarta un disparo.
2. Los disparos de estado crítico (los listados en B1) no pueden demorarse más de la ventana (2 s).
3. Extraer la lógica a una clase testeable (`DriverRefreshCoordinator` en `lib/driver_refresh_control.dart`) con **reloj y programador inyectables** (para simular tiempo en tests, sin esperas reales).
4. Mantener: timer de 12 s omitido si hubo refresco completo exitoso reciente; una sola carga completa concurrente.

### Para B2
1. Introducir un **contador de versión del estado** que se incremente cada vez que un refresco completo publica `cachedData`.
2. El refresco ligero guarda la versión al empezar; al terminar, si la versión cambió **o** hay un refresco completo en curso, **descarta su resultado** (y se re-encola si sigue siendo elegible). Alternativa válida: reconstruir sobre el `cachedData` más reciente reemplazando solo `rides`/`deliveries`, y solo si ese estado más reciente sigue sin viaje/entrega activos y en línea.
3. La decisión (descartar / aplicar / rebasar) debe ser una **función pura** testeable.

### Pruebas exigidas (nuevas, unitarias, con reloj simulado)
- B1-a: disparo a t+1 s tras un refresco → se ejecuta **una** vez a ≤ t+2 s.
- B1-b: 20 disparos en 1 s → 1 inmediato + como máximo 1 final.
- B1-c: disparo durante un refresco en curso → exactamente 1 repetición al terminar.
- B2-a: refresco ligero que empezó en la versión N y termina en N+1 → resultado descartado.
- B2-b: el estado final conserva `activeTrip` publicado por el refresco completo.
- B2-c: si el estado más reciente ya no es elegible (viaje activo/offline) → no se sobrescribe.
- Mantener las pruebas existentes (zona/canal, ventana de 12 s).

### Evidencia manual obligatoria antes de aprobar (Preview, 2 dispositivos conductor + 1 pasajero)
- A: medir llamadas a `my_current_country_trips_v2` del conductor en 60 s sin actividad (Supabase → Logs → API; filtro por esa ruta y el usuario). Meta ≤ 5.
- C: pasajero publica solicitud → oferta visible en el conductor en ≤ 2 s (3 repeticiones, tiempos).
- Nuevo D1: el pasajero cancela el viaje ~1 s después de un refresco del conductor → el conductor ve la cancelación en ≤ 3 s.
- Nuevo D2: llegar una solicitud nueva justo cuando se asigna un viaje → el viaje activo **no** desaparece.

---

## PROMPT PARA LA IA PROGRAMADORA (copiar y pegar completo)

```
Eres el programador de Express Delivery (Flutter/Supabase). No tienes más contexto que este mensaje y el repositorio jorge2610g/Expressdelivery.

LEE PRIMERO (en la rama claude/express-admin-audit-cp07ml): CHATGPT.md, AGENTS.md, docs/AI_ROLES_WORKFLOW.md, docs/AI_RESPONSE_FORMAT.md, docs/specs/SPEC-2026-10-10-driver-refresh-load.md y docs/reviews/REVIEW-PR150-driver-refresh-2026-10-10.md.

TAREA: corrige tu PR #150 (rama chatgpt/driver-refresh-throttle) según la revisión de Claude. Hay 2 fallos BLOQUEANTES:
- B1: _requestDriverRefresh descarta disparos dentro de la ventana de 2 s o con una carga en curso (puede dejar el panel con un viaje cancelado/asignado desactualizado ~22 s). Debe AGRUPAR con una ejecución final (trailing), sin descartar nunca. Extrae la lógica a un DriverRefreshCoordinator testeable con reloj y programador inyectables.
- B2: _refreshDriverAvailabilityOnly puede sobrescribir cachedData con un estado viejo si un refresco completo termina mientras tanto. Usa un contador de versión del estado; si cambió o hay carga completa en curso, descarta el resultado (o reconstruye sobre el estado más reciente solo si sigue elegible). La decisión debe ser una función pura.

Las instrucciones detalladas y las 6 pruebas unitarias exigidas (B1-a, B1-b, B1-c, B2-a, B2-b, B2-c) están en la revisión. No agregues nada fuera de alcance.

RESTRICCIONES: no toques main; no apliques migraciones ni despliegues; no modifiques backend; no fusiones tu PR. Si algo no está claro, pregunta y espera.

ANTES DE PROGRAMAR: confirma qué archivos vas a tocar.

ENTREGA: ejecuta flutter analyze --no-fatal-warnings --no-fatal-infos lib y flutter test. Regenera la evidencia de CI sobre el commit final (nuevo id de run y hashes de archivos) y cierra la PR temporal #151 y la rama chatgpt/driver-refresh-throttle-ci cuando termines. Responde en el PR usando EXACTAMENTE el formato de docs/AI_RESPONSE_FORMAT.md, respondiendo B1 y B2 punto por punto con el SHA del commit y la evidencia. Marca como PENDIENTE-MANUAL lo que requiera Preview (criterios A, C, D1, D2) y explica los pasos para el propietario. No marques PASS sin evidencia.
```
