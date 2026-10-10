# REVIEW PR #150 (r2) — perf: scope and throttle driver refresh load

- **PR:** https://github.com/jorge2610g/expressdelivery/pull/150
- **Rama:** `chatgpt/driver-refresh-throttle` · **Head revisado:** `a1231b1` ("fix: preserve trailing driver refresh events")
- **Base:** `claude/express-admin-audit-cp07ml`
- **Spec:** `docs/specs/SPEC-2026-10-10-driver-refresh-load.md`
- **Revisión anterior:** `docs/reviews/REVIEW-PR150-driver-refresh-2026-10-10.md`
- **Archivos:** `lib/driver_refresh_control.dart` (nuevo), `lib/video_style_home.dart`, `test/driver_refresh_control_test.dart` (nuevo), docs.

## Veredicto

**NO APROBADO.** B1 (coalescencia con trailing) queda resuelto en el coordinador. B2 (estado obsoleto) queda resuelto en el guard de versión para la lectura ligera. Pero hay **dos hallazgos bloqueantes** en la ruta de reconciliación: el PR afirma "una sola carga completa concurrente" y eso no es cierto.

## Evidencia propia (lectura del diff `a1231b1`)

1. `_reconcileDriverHomeInBackground()` marca `driverRefreshInFlight = true` y ejecuta `_load()` por su cuenta. El coordinador (`DriverRefreshCoordinator`) **no sabe** de esa carga: su `_inFlight` solo cubre `_startRequestedDriverRefresh`. Si se dispara una reconciliación mientras corre una carga coordinada (o al revés), se ejecutan **dos `_load()` concurrentes**.
2. En el mismo caso, el `whenComplete` de la carga coordinada pone `driverRefreshInFlight = false` mientras la reconciliación sigue corriendo, y viceversa. El flag compartido deja de representar algo real.
3. `_reconcileDriverHomeInBackground()` ahora empieza con `if (!mounted || driverRefreshInFlight) return;`. Antes ejecutaba siempre. Si una carga completa ya estaba en vuelo cuando se confirmó una acción (aceptar, cancelar, completar), **la reconciliación se descarta sin reintento**. La carga en vuelo pudo haber leído el estado previo a la acción, y la UI puede quedar con el estado optimista o viejo hasta el siguiente timer de 12 s (que además se salta si hubo carga completa reciente).
4. Coordinador (`lib/driver_refresh_control.dart`): la lógica de ventana/trailing es correcta para B1-a/b/c. `complete(succeeded: false)` no actualiza `_lastCompletedAt`, lo cual es correcto.
5. `driverAvailabilityRefreshDecision` y `driverRideRequestMatchesScope` cubren B2 y el filtro de zona/canal. Las pruebas son puras y cubren los casos declarados.
6. `_syncDriverRealtimeScope(null)` no suscribe ningún canal de solicitudes. Un conductor sin `zone_id` queda solo con el timer de 12 s. No es un fallo de este PR, pero debe quedar documentado.
7. Nombre de prueba B1-a: "trailing by two seconds". El assert real es 1 s después de la solicitud (2 s desde la finalización). El comportamiento es correcto; el nombre no.
8. No compilé ni ejecuté nada. `current` en el sort de `_refreshDriverAvailabilityOnly` debe existir en el `State`; el autor reporta `analyze` sin errores fatales, lo que lo respalda.

## Hallazgos

### Bloqueantes
- **R2-1 · Concurrencia de carga completa falsa.** Reconciliación y carga coordinada no comparten control de concurrencia real. Corrección: que `_reconcileDriverHomeInBackground()` pida una ejecución al coordinador (`_requestDriverRefresh()`) en lugar de llamar a `_load()` directo, o que el coordinador consulte el mismo flag/estado antes de `_start()`. Una sola vía de entrada a `_load()` para cargas completas.
- **R2-2 · Reconciliación post-acción descartada.** El `return` temprano por `driverRefreshInFlight` no puede descartar una reconciliación pedida tras una acción confirmada. Corrección: encolarla como trailing (vía coordinador), nunca descartarla.

### No bloqueantes
- **R2-3** Documentar en changelog y spec que un conductor sin `zone_id` no tiene Realtime de solicitudes (solo timer de 12 s).
- **R2-4** Renombrar `B1-a` a algo como "request 1 s after completion runs at window end (1 s later)".

## Pruebas exigidas antes de aprobar

1. Test de unidad: reconciliación pedida durante una carga coordinada no produce dos `_load()` simultáneos y produce exactamente una ejecución posterior (puede ser sobre el coordinador con reloj/programador simulados).
2. Test de unidad: acción confirmada mientras hay carga en vuelo → la reconciliación se ejecuta después (no se descarta).
3. `flutter analyze --no-fatal-warnings --no-fatal-infos lib` sin errores fatales y `flutter test` en verde, **sobre el commit final**.
4. CI regenerada sobre el commit final (la evidencia actual es del commit anterior).
5. Preview manual: criterios A, C, D1, D2 del spec, con conteo real de `my_current_country_trips_v2` (≤5/60 s), oferta visible ≤2 s, cancelación ≤3 s.

## Estado del trabajo de UI del pasajero

La rama `chatgpt/passenger-ui-architecture` **no existe** en el repo. No hay código de animaciones ni de UI del pasajero para revisar todavía.

---

## PROMPT PARA LA IA PROGRAMADORA

**Contexto.** Repo `jorge2610g/expressdelivery`, rama `chatgpt/driver-refresh-throttle`, PR #150. Solo Flutter/Dart en `lib/` y `test/`. Prohibido tocar Supabase, SQL, Edge Functions y Producción.

**Leer primero.** `docs/specs/SPEC-2026-10-10-driver-refresh-load.md`, `docs/reviews/REVIEW-150-driver-refresh-2026-10-10-r2.md` (este archivo), `lib/driver_refresh_control.dart`, `lib/video_style_home.dart` (buscar `_DriverMapHomeState`, `_reconcileDriverHomeInBackground`, `_startRequestedDriverRefresh`, `_refreshDriverAvailabilityOnly`).

**Tarea.**
1. (R2-1) Hacer que toda carga completa del conductor pase por `DriverRefreshCoordinator`. `_reconcileDriverHomeInBackground()` debe llamar a `_requestDriverRefresh()` en lugar de `_load()` directo. Eliminar el `driverRefreshInFlight` duplicado o derivarlo del coordinador.
2. (R2-2) Eliminar el `return` temprano de `_reconcileDriverHomeInBackground()` cuando hay carga en vuelo: la petición debe encolarse como trailing, nunca descartarse.
3. (R2-3) Anotar en `docs/CHANGELOG_ACTIVE.md` que sin `zone_id` no hay Realtime de solicitudes.
4. (R2-4) Renombrar el test `B1-a` para que describa el comportamiento real.
5. Añadir los tests del punto "Pruebas exigidas" 1 y 2 en `test/driver_refresh_control_test.dart` (usar el coordinador con reloj/programador simulados).

**Restricciones.** Cambios mínimos. No cambiar la lógica de B1/B2 ya aprobada en el coordinador ni el filtro de zona/canal. Sin migraciones, RPC ni Edge Functions. No desplegar.

**Cómo probar.** `flutter analyze --no-fatal-warnings --no-fatal-infos lib` (sin errores fatales), `flutter test` (todo en verde), y una CI nueva sobre el commit final. Reportar el conteo de tests antes/después.

**Formato de devolución.** Seguir `docs/AI_RESPONSE_FORMAT.md`: commit hash, lista de archivos cambiados, salida literal de analyze y test, enlace a la nueva CI, y qué queda pendiente de la prueba manual Preview.
