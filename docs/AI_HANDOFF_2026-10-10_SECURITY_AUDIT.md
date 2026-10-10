# Handoff 2026-10-10 — Auditoría, separación Preview/Producción y correcciones

> **Para cualquier IA o desarrollador que continúe.** Resume qué se hizo, qué se
> quitó/restringió, qué quedó pendiente y cómo verificar o revertir cada cosa.
> Complementa (no reemplaza) `docs/AI_HANDOFF_2026-10-06_MASTER.md`.
> Detalle técnico: `docs/AUDIT_2026-10-10_ESTADO_Y_PLAN.md`,
> `docs/EDGE_FUNCTIONS_INVENTORY.md`, `docs/CHANGELOG_ACTIVE.md`.
> Rama de trabajo: `claude/express-admin-audit-cp07ml` → PR #148 (Expressdelivery).

---

## 1. Arquitectura confirmada por el propietario (REGLA)

- **Una sola app** Flutter (`lib/mobile_main.dart`) → APK y AAB de Producción.
- **Una sola base de datos**: Supabase `zgpijrznvaskgcmauwxx`.
- **Dos entornos dentro de esa base**: `preview` y `production`, separados por
  canal (`runtime_channel`, `account_runtime_bindings`, shadow
  `admin_environment_config`, RPC con `p_channel`).
- **Admin**: dos paneles (`admin.expressviajes.online/` y `/preview/`) sobre el
  mismo Supabase; `ADMIN_ENV` decide el canal, nunca la base.
- **Supabase `xbphilqezmwfjfpdbwad`** ("Express Preview" físico) = **solo banco
  de pruebas** de migraciones y Edge Functions. Ni la app ni el Admin se
  conectan a él. Flujo: probar ahí → aplicar en `zgpijrznvaskgcmauwxx` **con
  autorización del propietario**.
- Un solo proyecto Firebase con dos apps (Producción/Preview). No se tocó Firebase.

## 2. Qué se hizo (y dónde está)

### Código de la app
| Cambio | Archivo | Estado |
|---|---|---|
| `passenger_ads_mobile.dart` estaba truncado desde `e37d7be` (reemplazo JS con `$'`); Android no compilaba | `lib/passenger_ads_mobile.dart` | Reparado (sin cambio funcional) |
| Falso positivo `dart:js_util` (archivo solo Web) | `lib/push_notifications_web.dart` | `// ignore` documentado |
| CI solo analizaba 7 archivos | `.github/workflows/express-single-app-qa.yml` | Ahora `flutter analyze lib` |

### Base de datos (aplicado en QA y luego en Producción, con autorización)
| Etapa | Migración | Qué hace |
|---|---|---|
| E1 | `supabase/migrations/20261010120000_admin_production_write_guard.sql` | 75 RPC `admin_*` de **escritura** sin `p_channel` exigen `admin_assert_environment('production')`; 10 internas sin EXECUTE para clientes; `admin_environment_config_upsert` valida `p_environment`; `admin_users.allow_production DEFAULT false` |
| E1b | `supabase/migrations/20261010160000_admin_production_read_guard.sql` | 30 RPC de **lectura** con datos personales exigen Producción; 7 internas sin EXECUTE |
| E4 | `supabase/migrations/20261010140000_driver_auto_approval_on_verified_documents.sql` | Conductor pasa a `approved` automáticamente al verificar todos sus documentos obligatorios (helper `driver_auto_approve_if_complete`, sin trigger) |
| E6 | `supabase/migrations/20261010180000_least_privilege_anon_and_table_grants.sql` | `anon` sin escritura en tablas; nadie del cliente con TRUNCATE/TRIGGER/REFERENCES; 13 funciones sin EXECUTE para `anon` |
| E3 | `20261009222741_…`, `20261009232017_…`, `20261009233719_…` | Migraciones que ya estaban aplicadas en Producción y faltaban en el repo (hash idéntico verificado) |

Abiertas a propósito (no tocar sin razón): `admin_access_context`,
`admin_has_panel_access`, `admin_can_access_zone`, `admin_effective_zone_id`,
`admin_country_list_scoped`, `admin_zone_list_scoped`,
`admin_zone_list_for_country`, `admin_log_action`,
`admin_set_dynamic_pricing_qa_override`; para `anon` (previas al login):
`app_runtime_config`, `app_geo_policy`, `latest_app_release`,
`phone_country_catalog`, `auth_login_guard_*`, `service_zone_id_for_point`,
`effective_fare_rule`, `zone_ride_payment_methods`,
`driver_floating_offer_config`, `driver_priority_settings_for`.

### App: panel del conductor ante cortes de red
- `lib/video_style_home.dart`: un error transitorio ya no reemplaza el panel (se conserva `cachedData`); sin datos, mensaje amigable + Reintentar (`expressFriendlyLoadError`). Test: `test/express_friendly_load_error_test.dart`.

### Datos
- Conductor `e3656702…` (BO, Producción), atascado "en revisión" con todo
  aprobado → aprobado con autorización (notificación + auditoría registradas).

### Edge Functions (Producción)
| Función | Versión | Cambio |
|---|---|---|
| `zone-payment-admin` | v17 | exige permiso de Producción (credenciales Mercado Pago) |
| `driver-subscription-admin` | v20 | exige permiso de Producción (credenciales VeriPagos) |
| `marketplace-payments` | v19 | fix `ReferenceError` en `plus_verify` |
| `express-push-dispatch` | v38 | secreto en tiempo constante; quitar `.isEmpty`; **sin** `894348c` |
| 7 funciones retiradas (Didit, phone-otp, health-checks) | — | código versionado en repo (stubs 410/204) |

## 3. Qué se quitó o restringió (posibles efectos)

- Un admin **sin `allow_production`** recibe `No autorizado para el entorno
  production` en cualquier RPC admin sin canal (lectura o escritura) y en las
  Edge Functions de credenciales de pago. Es intencional.
- Funciones internas (p. ej. `admin_set_driver_approval`, `admin_user_detail`,
  `admin_driver_detail`, `admin_trip_detail`, `admin_upsert_zone_v3`) ya **no**
  se pueden llamar desde clientes: usar las versiones `*_v2` con `p_channel`.
- `anon` ya no tiene permisos de escritura en tablas públicas.
- Nuevos `admin_users` nacen con `allow_production=false`.
- El Laboratorio QA (grupos de auditoría) requiere admin con Producción.

## 4. Pendiente (en orden sugerido)

1. **Propietario**: probar guardado en panel Producción con la cuenta original
   (verificación real de E1/E1b/E6).
2. **Propietario**: Supabase → Authentication → URL Configuration → Redirect
   URLs debe incluir `https://admin.expressviajes.online/preview/`; probar
   login Google en Admin Preview.
3. **Propietario**: activar *Leaked password protection* (Auth) en ambos proyectos.
4. **E2**: cuenta Google nueva solo-Preview (la actual
   `expressdelivery.soporte@gmail.com` también es conductor real de
   Producción). Después: quitar admin a esa cuenta y decidir si
   `scuentas150@gmail.com` queda solo con Producción.
5. Decidir `894348c` (Preview `ride_request` solo-datos para la oferta
   flotante): está en el repo, **no** en Producción. No desplegar
   `supabase/functions/express-push-dispatch/index.ts` tal cual sin decidirlo.
6. `express-load-lab`: corrección en repo (exige permiso Preview), no
   desplegada; su código solo se comparó por fragmentos.
7. Compilar APK desde `main` reparado (etiqueta `native-qa`) y probar banner AdMob en Preview.
8. P1 del plan: Operaciones en Vivo (Admin sin Realtime), tarifas por
   país/zona, rendimiento (26 `Timer.periodic`, 13 canales Realtime en la app).
8b. Rendimiento conductor — **implementado en `chatgpt/driver-refresh-throttle`, pendiente de aceptación manual Preview A–C**: baseline ~20 llamadas/min a `my_current_country_trips_v2`; `ride_requests` y `zone_service_catalog` ahora se filtran por `zone_id`, `channel` se valida en cliente, el refresco completo entra por un throttle único de 2 s sin concurrencia y el timer de 12 s omite lecturas recientes. Tests unitarios cubren throttle/filtro. Falta medir el conteo runtime después (objetivo ≤5/60 s sin actividad) y oferta real ≤2 s con dos dispositivos antes de marcarlo aprobado. Sin backend ni Producción. Ver spec y changelog 2026-10-10.
9. Fusionar PR #148 y cerrar PR #145/#146/#147 (cubiertas por E3).

## 5. Cómo verificar / revertir

- Respaldos en Producción y QA:
  `public.admin_function_backup_20261010` (definiciones+ACL; prefijos `E1b:`, `E4:`)
  y `public.acl_backup_20261010_e6` (ACL de tablas y funciones).
- Rollbacks manuales: `docs/backups/20261010_E1_rollback.sql`,
  `…_E1b_rollback.sql`, `…_E4_rollback.sql`, `…_E6_rollback.sql`
  (probados en QA dentro de transacción: 0 diferencias).
- Edge Functions: `docs/backups/edge-functions/express-push-dispatch.v37.prod.ts`
  (rollback exacto) y `.v38.prod.ts`.
- Pruebas de permisos: transacción con `set_config('request.jwt.claims', …)`,
  `set local role authenticated|anon`, bloques `do $$ … exception … $$` que
  escriben en una tabla temporal, y `rollback`. Ver ejemplos en el changelog.

## 6. Lecciones para la próxima IA (IMPORTANTE)

- **El código desplegado puede no estar en git.** `express-push-dispatch` v37
  no coincidía con ninguna versión del repo. Antes de desplegar, descargar lo
  desplegado (`get_edge_function`) y comparar **byte a byte**; la comparación
  por fragmentos dio un falso "coincide".
- La herramienta MCP de despliegue exige enviar el archivo completo. Para
  funciones críticas: reconstruir por dos vías independientes, `diff`, `deno
  check`, desplegar en QA, comparar `ezbr_sha256` QA vs Producción y tomar una
  línea base de respuestas antes/después.
- El contenedor no tiene salida a `*.supabase.co`; para invocar funciones se
  usó `pg_net` desde la propia base (`net.http_get/http_post` +
  `net._http_response`).
- No hay JWT de usuarios: la lógica "admin sin Producción" se probó en SQL;
  en Edge Functions solo se probó arranque y rechazo.
- Inyección de guards: plpgsql, insertar tras el primer `BEGIN` del cuerpo,
  respaldar antes, idempotente por marcador (`E1-20261010`), abortar si no hay
  punto de inserción.
- Al revocar EXECUTE a funciones internas, verificar antes que los wrappers
  sean SECURITY DEFINER de `postgres` y que ningún cliente las llame (grep en
  `Expressdelivery/lib`, `adminexpress/lib`, `supabase/functions`).
- Un `delete` en una consulta de prueba puede ser cancelado por el sistema de
  permisos aunque esté dentro de una transacción revertida: preferir `update`.
