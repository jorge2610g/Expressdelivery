# Auditoría Express + AdminExpress · 2026-10-10

> Informe de solo lectura. **No se modificó** código de producto, Supabase
> (Producción ni QA), Edge Functions, Auth, APK/AAB, Play ni páginas web.
> Evidencia obtenida con: `flutter analyze`/`flutter test` (Flutter 3.47.7),
> consultas SQL de solo lectura, advisors de Supabase, logs de Auth y API de GitHub.

## 0. Acceso verificado

| Recurso | Estado |
|---|---|
| `jorge2610g/Expressdelivery` (main `f750078`) | lectura + push |
| `jorge2610g/Adminexpress` (main `25b682a`) | lectura + push |
| Supabase Producción `zgpijrznvaskgcmauwxx` | SQL, migraciones, Edge Functions, advisors, logs |
| Supabase QA físico `xbphilqezmwfjfpdbwad` | SQL, migraciones, Edge Functions, advisors |
| Supabase Auth → URL Configuration (Redirect URLs) | **sin acceso** con las herramientas disponibles |
| Google Cloud / Play Console / Firebase / dispositivos | **sin acceso** |

## 1. Estado real de los repositorios

### Expressdelivery
- Versión `1.6.1+169`; ~57 k líneas Dart. Archivos muy grandes:
  `video_style_home.dart` (15 816), `express_delivery_v2_page.dart` (6 861),
  `connected_experience.dart` (6 112).
- `flutter test`: **54/54 OK** (12 archivos de test).
- `flutter analyze`: **79 errores**:
  - 78 en `lib/passenger_ads_mobile.dart`: el archivo quedó **truncado** en el
    commit `e37d7be` (2026-10-09, AdMob). Línea 24 termina en
    `RegExp(r'^ca-app-pub-[0-9]{16}/[0-9]{10}` y falta el resto de la función.
    El contenido perdido no existe en ningún commit.
  - 1 en `lib/push_notifications_web.dart`: `dart:js_util` no existe en 3.47.7
    (CI usa 3.47.5: confirmar).
  - **Impacto:** la Web compila (importación condicional), por eso CI Web siguió
    verde; **cualquier APK/AAB compilado desde `main` falla**.
- Migraciones en repo: 160 archivos; prefijos duplicados (041, 055, 056, 066,
  089, 126) y mezcla de esquemas `NNN_` / timestamp.
- Edge Functions en repo: 11. Producción tiene 18.
- PR abiertos: 11 (#144–#147 borradores de seguridad; #15, #16, #65, #80, #100,
  #110, #111 antiguos).

### Adminexpress
- `flutter analyze`: 0 errores (379 avisos/infos). `flutter test`: 5/5 OK.
- `admin_control_sections.dart` 9 567 líneas, `admin_panel.dart` 5 095.
- Ambas páginas (`/` y `/preview/`) usan **el mismo** Supabase Producción;
  `ADMIN_ENV` solo cambia el canal (`p_channel`) y la clave de sesión local.
- PR #51 a #55 fusionados (incluye #54 sesiones separadas y #55 retorno OAuth,
  fusionado 2026-10-10 00:16 UTC). Abiertos: #33, #5.
- Live Ops: 0 suscripciones Realtime en Admin (refresco por polling/Futures).

## 2. Arquitectura actual vs objetivo

| Aspecto | Actual (verificado) | Objetivo |
|---|---|---|
| App móvil | 1 código Flutter, `lib/mobile_main.dart`; Web `lib/web_preview.dart` | igual |
| Datos Preview | **mismo** proyecto Producción, separado por `runtime_channel`, `account_runtime_bindings` y shadow `admin_environment_config` | aislamiento verificable en servidor; QA físico para pruebas de riesgo alto |
| Admin Preview | misma BD; autorización por `allow_preview/allow_production` **solo en RPC con `p_channel`** | toda RPC de escritura valida entorno |
| QA físico | 181 migraciones (Prod 214), 4 Edge Functions (Prod 18), 3 usuarios, 1 admin | esquema alineado + contratos antes de usarlo |
| Release Android | gate único candidato firmado → QA → promover sin recompilar | igual, con `main` compilable |

## 3. Funciones implementadas / pendientes (resumen)
- Implementado y verificado en BD: guards fail-closed de Preview en
  `admin_zone_coverage_save` y `admin_distance_fare_steps_replace`; RLS en todas
  las tablas públicas; ninguna política de escritura para `anon`; buckets
  privados salvo `app-releases` (vacío); verificación manual de identidad por
  partes (frente/reverso/selfie); cotización de tarifa sin "$5" falso en código.
- Pendiente / incompleto: ver hallazgos §4 y §6.

## 4. Riesgos que podrían romper Producción (ordenados)

### P0-1 · La cuenta Admin "Preview-only" puede administrar Producción (confirmado por código, no ejecutado)
- `expressdelivery.soporte@gmail.com`: `access_role=super_admin`,
  `allow_preview=true`, `allow_production=false`.
- `is_admin()` solo exige `super_admin` activo; **no** mira `allow_production`.
- **218** funciones `admin_*` SECURITY DEFINER ejecutables por `authenticated`;
  **167** sin `p_channel`; **88** de ellas escriben (`insert/update/delete`) y
  **ninguna** llama `admin_environment_allowed`/`admin_assert_environment`.
  Ejemplos: `admin_upsert_fare_rule`, `admin_upsert_zone*`, `admin_settings_update`,
  `admin_set_zone_payment_provider`, `admin_resolve_wallet_topup`,
  `admin_publish_build`, `admin_promote_single_app_candidate`,
  `admin_send_announcement*`, `admin_set_driver_approval` (v1).
- **Escalada:** `admin_set_panel_access` solo exige `is_admin()` y
  `admin_users.allow_production` tiene `DEFAULT true` ⇒ la cuenta Preview puede
  crear otro `super_admin` con acceso a Producción o desactivar al admin original.
- La UI de Preview bloquea módulos (`_previewScopedModules`), pero eso no
  protege llamadas directas a `/rest/v1/rpc`.

### P0-2 · `main` de Express no compila para Android
Ver §1. Bloquea cualquier release y cualquier fix urgente móvil.

### P0-3 · La cuenta Admin Preview es también un conductor de Producción
`expressdelivery.soporte@gmail.com` = usuario `8e6c652c…`, conductor CL
`approved`, runtime `production`, verificado por Didit. Mezcla identidad
administrativa Preview con una cuenta operativa real.

### P1 · Deriva repo ↔ servidor
- Aplicadas en Producción y **ausentes en `main`**:
  `admin_zone_coverage_preview_fail_closed_20261009`,
  `admin_distance_fare_steps_preview_fail_closed_20261009`,
  `admin_settings_explicit_channel_privileges_20261009` (PR borrador #145–#147).
- Edge Functions desplegadas sin código en repo: `didit-identity`,
  `didit-webhook`, `didit-identity-prod`, `didit-webhook-prod`, `phone-otp`,
  `unimatrix-health-check`, `zego-health-check`.

### P1 · Seguridad complementaria
- 28 funciones SECURITY DEFINER ejecutables por `anon` (incluye 9 `admin_*_v2`);
  hoy terminan en `is_admin()` ⇒ no explotables, pero conviene revocar.
- `anon` tiene GRANT INSERT/UPDATE/DELETE sobre 33 tablas (RLS lo bloquea hoy).
- Protección de contraseñas filtradas desactivada en Auth (ambos proyectos).
- `express-push-dispatch` compara secreto con `!==` (no tiempo constante).

## 5. Diferencias Preview (QA físico) vs Producción
- Migraciones: 181 vs 214.
- Tabla ausente en QA: `zone_distance_fare_steps`.
- Funciones solo en Prod: `admin_admob_settings_get/update`,
  `admin_distance_fare_steps_get`, `admin_zone_coverage_get`,
  `dispatch_push_notification`. Solo en QA: `preview_bind_test_account`.
- Edge Functions QA: `zego-call`, `driver-subscription-payments`,
  `marketplace-payments`, `express-push-dispatch` (Prod: 18).
- Ningún cliente (app ni Admin `main`) apunta hoy a QA físico.

## 6. Errores reproducibles con evidencia

### 6.1 Conductor queda "en revisión" tras aprobar fotos (reproducido en datos)
- Conductor `e3656702…` (BO, Producción): `driver_documents.status=verified`,
  `review_parts.front/back/selfie=approved`, `identity_verifications=verified/express_manual`,
  pero `driver_profiles.approval_status=pending`.
- Causa: `admin_driver_kyc_bolivia_manual_review_part` actualiza documento e
  identidad y notifica "Fotografía aprobada", pero **no** cambia
  `approval_status`. Se requiere un segundo paso manual
  (`admin_set_driver_approval_v2`) que el flujo de revisión no solicita.
- Queda además una parte `profile` rechazada de una versión anterior; el trigger
  ya no la cuenta, pero la UI puede mostrarla.

### 6.2 Build Android roto
`flutter analyze` → 78 errores en `lib/passenger_ads_mobile.dart` (ver §1).

### 6.3 OAuth Admin Preview sin verificación end-to-end
- Último login de la cuenta Preview: 2026-10-10 00:10 UTC, **antes** del
  despliegue de PR #55 (00:16 UTC). No hay intentos posteriores en logs.
- La lista de Redirect URLs de Supabase Auth no es legible con mis herramientas.

## 7. Plan por etapas (menor riesgo primero)

| Etapa | Contenido | Riesgo | Autorización |
|---|---|---|---|
| E0 | Este informe; dejar `main` compilable: reescribir `bannerUnitId` en `passenger_ads_mobile.dart` + CI `flutter analyze lib/mobile_main.dart` obligatorio | Bajo (Dart, sin backend) | PR normal |
| E1 | Contener P0-1 **sin bloquear al admin original**: (a) `allow_production DEFAULT false`; (b) nueva función `admin_require_production()` = `is_admin() and admin_environment_allowed('production')`; (c) añadirla al inicio de las 88 RPC sin canal, por lotes (primero `admin_set_panel_access`, builds/promoción, tarifas/zonas/pagos/billetera), migración versionada + prueba en QA físico + prueba con ambas cuentas | Alto (backend/permisos) | **Requiere tu OK** antes de aplicar en Producción |
| E2 | Separar identidad: crear cuenta Google dedicada Preview que no sea conductor; luego retirar `allow_preview` de la cuenta original solo tras login verificado | Medio | Requiere tu OK + acción tuya en Google/Auth |
| E3 | Sincronizar repo con servidor: versionar las 3 migraciones (sin re-ejecutar), descargar y versionar las 7 Edge Functions | Bajo | PR normal |
| E4 | Aprobación de conductores: opción A — auto-promover `approval_status` cuando la identidad pasa a `verified` y no faltan requisitos; opción B — la UI de revisión muestra "Identidad verificada → Aprobar conductor". Corregir datos de `e3656702` solo tras tu decisión | Medio | **Decisión de negocio** |
| E5 | Alinear QA físico (migraciones faltantes, Edge Functions) y usarlo para pruebas de migración | Medio | Requiere OK |
| E6 | Hardening complementario: revocar `anon` en RPC/tablas, leaked-password protection, comparación constante del secreto push | Bajo-medio | Requiere OK |
| E7 | Rendimiento: inventario de 26 `Timer.periodic` y 13 canales Realtime en la app, 157 llamadas RPC en Admin; caché y Realtime en Live Ops | Medio | PR por módulo |
| E8 | Release: candidato firmado desde `main` reparado → QA físico → promoción | Alto | Requiere OK |

## 8. Pruebas antes de integrar
- `flutter analyze` (ambos entrypoints) y `flutter test` en ambos repos.
- `flutter build web` (Express y Admin `ADMIN_ENV=production|preview`).
- Backend: aplicar primero en QA físico; matriz de permisos con cuentas
  {admin prod+preview, admin preview-only, usuario normal, anon} × RPC tocadas,
  verificando `No autorizado` donde corresponde y éxito donde no debe cambiar.
- Diff de definiciones (`pg_get_functiondef`) antes/después; advisors de seguridad.
- Regresión de contratos con APK instalados (mismas firmas de RPC).

## 9. Respaldo y rollback
- Antes de cada migración: guardar `pg_get_functiondef` de cada función tocada en
  `docs/backups/` y una migración inversa lista.
- Cambios de permisos: siempre aditivos; nunca revocar al admin original en el
  mismo paso.
- Ramas de trabajo + PR; nada se fusiona a `main` ni se aplica a Producción sin tu OK.

## 10. Qué puedo hacer solo / qué requiere tu autorización
- **Solo:** lectura de repos/BD/logs, ramas, PR, tests, documentación, migraciones
  en QA físico tras confirmar alcance.
- **Con tu OK explícito:** cualquier migración o despliegue en Producción,
  cambios de permisos/roles, Edge Functions, merges a `main`, builds firmados.
- **Solo tú:** Supabase Auth → Redirect URLs, Google Cloud OAuth, Play Console,
  pruebas en dispositivo físico, decisiones de negocio (E4).

## 11. Avance

- **E0** (PR #148): `passenger_ads_mobile.dart` restaurado; CI analiza todo `lib/`.
- **E1**: migración `20261010120000_admin_production_write_guard.sql` aplicada y probada en QA físico y **aplicada en Producción** (2026-10-10, autorizada). Detalle de pruebas en `CHANGELOG_ACTIVE.md`.
- **E4**: aprobación automática aplicada en QA y Producción (`20261010140000_...`). Conductor `e3656702` corregido (aprobado) con autorización.
- **E3**: 3 migraciones y 7 Edge Functions versionadas desde Producción (verificadas); sin despliegues.
- **E1b**: guard de lecturas aplicado en QA y Producción (`20261010160000_...`).
- **E6**: mínimo privilegio aplicado en QA y Producción (`20261010180000_...`). Pendiente: Leaked password protection (panel Supabase) y comparación de tiempo constante en `express-push-dispatch` (requiere despliegue).
