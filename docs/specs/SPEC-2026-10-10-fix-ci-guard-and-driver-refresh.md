# SPEC 2026-10-10 — Corrección: guard de migraciones (CI rojo en PR #148) y reconciliación del conductor (PR #150)

**Estado:** lista para la IA programadora. Claude revisa después.
**Alcance:** solo `docs/ci/guard_migration_safety.py` (CI) y `lib/video_style_home.dart` + `lib/driver_refresh_control.dart` + tests. Sin cambios en SQL, Edge Functions ni Producción.

## Evidencia

1. **CI rojo en PR #148** (job `validate`, run `38022028027`, job `114124881136`). Log literal:
   `FAIL: supabase/migrations/20261010180000_least_privilege_anon_and_table_grants.sql: operation TRUNCATE requires separately reviewed manual migration`
   Causa: el guard marca `TRUNCATE` como operación destructiva. La migración E6 solo hace `REVOKE truncate, references, trigger ... FROM authenticated/anon` (quitar privilegios, no crearlos). La migración ya fue aplicada en Producción con autorización, así que no debe editarse para pasar el guard.
2. **PR #150, bloqueante R2-1:** la reconciliación en segundo plano (`_reconcileDriverHomeInBackground`) llama a `_load()` directo, fuera de `DriverRefreshCoordinator`. Puede haber dos cargas completas en paralelo.
3. **PR #150, bloqueante R2-2:** `_reconcileDriverHomeInBackground` retorna sin hacer nada si `driverRefreshInFlight` es true. Una reconciliación pedida tras una acción confirmada se pierde.

Detalle de R2: `docs/reviews/REVIEW-150-driver-refresh-2026-10-10-r2.md`.

## Tarea A — guard de migraciones (PR #148)

1. En `docs/ci/guard_migration_safety.py`, permitir `REVOKE` de privilegios (`TRUNCATE`, `REFERENCES`, `TRIGGER`, `INSERT`, `UPDATE`, `DELETE`) sin exigir revisión manual. Seguir exigiendo revisión manual para `GRANT TRUNCATE`, `DROP`, `TRUNCATE TABLE` y similares.
2. No modificar `supabase/migrations/20261010180000_least_privilege_anon_and_table_grants.sql`.
3. Agregar un caso de prueba al guard: `REVOKE truncate, references, trigger ON ALL TABLES IN SCHEMA public FROM anon` debe pasar; `TRUNCATE TABLE public.x` debe fallar.
4. Verificar localmente: `python3 docs/ci/guard_migration_safety.py --base-sha f750078915014089541a80f0190a56c381d153bd` debe terminar con código 0 sobre el estado actual del PR.

## Tarea B — reconciliación del conductor (PR #150)

1. Toda carga completa debe entrar por `DriverRefreshCoordinator`. En `_reconcileDriverHomeInBackground()`, reemplazar la llamada directa a `_load()` por `_requestDriverRefresh()`. Quitar el flag `driverRefreshInFlight` duplicado o derivarlo del coordinador. Debe existir una sola vía de entrada a `_load()` para cargas completas.
2. Eliminar el `return` temprano de `_reconcileDriverHomeInBackground()` por carga en vuelo. Una petición de reconciliación debe encolarse como trailing, no descartarse.
3. Renombrar el test `B1-a` para que describa el comportamiento real: "request 1 s after completion runs at window end (1 s later)".
4. Anotar en `docs/CHANGELOG_ACTIVE.md`: sin `zone_id` el conductor no tiene Realtime de solicitudes y depende del timer de 12 s.
5. Agregar tests en `test/driver_refresh_control_test.dart` con reloj y programador simulados:
   - R2-1: reconciliación pedida durante una carga coordinada produce exactamente una ejecución posterior, nunca dos simultáneas.
   - R2-2: reconciliación pedida durante una carga en vuelo se ejecuta después, no se descarta.

## Restricciones

- Cambios mínimos. No cambiar la lógica B1/B2 ya aprobada del coordinador ni el filtro de zona/canal.
- No tocar SQL, migraciones, Edge Functions, Producción ni Firebase.
- No usar `--no-verify`, no saltar tests, no desactivar el guard.

## Cómo probar

1. `python3 docs/ci/guard_migration_safety.py --base-sha f750078915014089541a80f0190a56c381d153bd` → código 0.
2. `flutter analyze --no-fatal-warnings --no-fatal-infos lib` → sin errores fatales.
3. `flutter test` → todo en verde. Reportar conteo antes y después.
4. CI nueva sobre el commit final: `validate` y `Shared Flutter checks` en verde.

## Formato de devolución

Seguir `docs/AI_RESPONSE_FORMAT.md`: commit hash, archivos cambiados, salida literal de guard, analyze y test, enlace a la CI nueva, y lo pendiente de prueba manual Preview (criterios A, C, D1, D2 de la spec de conductor).

---

## PROMPT PARA LA IA PROGRAMADORA

Repo `jorge2610g/Expressdelivery`. Trabaja en la rama `chatgpt/driver-refresh-throttle` (PR #150) y, para la tarea A, en la rama del PR #148 (`claude/express-admin-audit-cp07ml`, o la rama donde esté el guard, indícalo en tu respuesta).

Lee primero: `docs/specs/SPEC-2026-10-10-fix-ci-guard-and-driver-refresh.md` (este archivo), `docs/reviews/REVIEW-150-driver-refresh-2026-10-10-r2.md`, `docs/ci/guard_migration_safety.py`, `lib/driver_refresh_control.dart`, `lib/video_style_home.dart` (busca `_reconcileDriverHomeInBackground`, `_requestDriverRefresh`, `_startRequestedDriverRefresh`).

Haz exactamente lo que dice la spec, Tarea A y Tarea B. No toques SQL, migraciones, Edge Functions, Producción ni Firebase. No hagas nada que la spec no pida. Si algo de la spec no es claro, detente y pregunta antes de adivinar.

Prueba con: el comando del guard, `flutter analyze --no-fatal-warnings --no-fatal-infos lib` y `flutter test`. Después de subir, confirma que la CI del commit final está en verde.

Devuelve el resultado con el formato de `docs/AI_RESPONSE_FORMAT.md`.
