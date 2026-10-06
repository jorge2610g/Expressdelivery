## 2026-10-06 · Corrección del auditor para Preview +155

- el auditor debe ejecutar **el APK Preview publicado exacto** (`preview-shorebird-v1.6.0-buildNNN/app-release.apk`) cuando el artefacto contiene `x86_64`; no debe reconstruir otro APK de emulador y luego atribuir sus fallos a la release;
- `qa_driver_request_flow.py` ya no lee `service_zones` ni `zone_service_catalog` directamente; usa el RPC de aplicación `app_zone_context` con la cuenta QA autenticada para obtener la misma zona/servicios que ve la app;
- no se abrieron permisos `SELECT` adicionales sobre tablas operativas solo para hacer pasar QA;
- un fallo de infraestructura QA debe seguir bloqueando certificación, pero **no** debe registrarse como regresión de producto sin evidencia correlacionada.
# Express QA Automation

> Estado actualizado 2026-10-04: leer también `docs/AI_HANDOFF_2026-10-04.md`. El workflow actual provisiona identidades QA efímeras, ejecuta APK Preview x86_64, Maestro, health snapshots y un Evidence Gate. Un run rojo no implica por sí solo una regresión de producto.

Express Preview has an external QA pipeline designed to catch regressions without relying on manual testing.

## Layers

1. **Android APK smoke test**
   - Downloads the real published Express Preview base APK.
   - Installs it on an Android emulator.
   - Applies the latest Shorebird patch through the in-app updater.
   - Verifies that the app opens and the authentication UI is usable.
   - Stores screenshots and Maestro reports.

2. **Visual AI audit (optional)**
   - Uses Maestro `assertNoDefectsWithAI` and `assertWithAI`.
   - Looks for clipped text, overlaps, misaligned icons, abnormal white space and bad margins.
   - Enabled when the repository secret `MAESTRO_CLOUD_API_KEY` is configured.

3. **Authenticated smoke tests (optional)**
   - Passenger account secrets:
     - `QA_PASSENGER_EMAIL`
     - `QA_PASSENGER_PASSWORD`
   - Driver account secrets:
     - `QA_DRIVER_EMAIL`
     - `QA_DRIVER_PASSWORD`
   - Credentials are never committed to the repository.

4. **Backend observability**
   - `app_error_logs`: Flutter/runtime/push/UI errors.
   - `app_flow_events`: ride requests, driver offers, trips, notifications, push-token changes and FCM dispatch results.
   - The `express-qa-monitor` Edge Function is callable only from the GitHub QA workflow via GitHub OIDC.

5. **Automatic incident**
   - Failed QA runs upload screenshots/reports/logs.
   - A GitHub issue with label `qa-auto` is opened or updated automatically.

## Regla de identidad de la versión auditada

QA no toma `main` como identidad de producto ni usa tags históricos fijos.

Antes del emulador:

- consulta `app_release_gate` mediante el worker OIDC;
- exige que la Preview vigente tenga la misma versión/build declarada actualmente en `main`;
- bloquea si existen cambios sensibles de app posteriores al SHA Preview sin una nueva Preview;
- hace checkout del `preview_commit_sha` exacto;
- verifica el release Shorebird correspondiente a esa versión/build.

Esto evita certificar accidentalmente una versión antigua mientras el equipo cree estar probando la actual.

## 2026-10-06 · Coordenadas del conductor QA

Regla reforzada para el smoke de solicitud al conductor:

- `.github/scripts/qa_driver_request_flow.py` **no puede mover al conductor a una ciudad hard-coded**;
- la ubicación autoritativa es la que dejó `express-qa-provision` en `driver_profiles`;
- el script lee `latitude/longitude/city/zone_id` del conductor QA y crea la solicitud alrededor de ese punto;
- la categoría sintética debe ser compatible con el vehículo provisionado; el QA actual usa `motorcycle`;
- la moneda se toma de `dynamic_pricing_quote`, por lo que Trinidad usa BOB y otra zona puede devolver su moneda propia;
- un rechazo de cobertura al intentar forzar otra ciudad se clasifica como **fallo del harness**, no como regresión de producto.

Este cambio corrige el run que intentó mover el conductor de Trinidad a coordenadas fijas de Iquique y terminó en HTTP 400 antes de sembrar la solicitud.


## When it runs

- After a successful **Express Preview Shorebird Code Push**.
- Every 6 hours.
- Manually through **Actions → Express QA Auditor**.

## Next expansion

Once the dedicated passenger and driver QA accounts are connected, add the full synthetic journey:

request → offer → accept → driver arriving → driver waiting → PIN → in progress → completed.

That flow should be correlated with `app_flow_events` so the test validates both the visual UI and the real backend state.


## Verdicts actuales

El Evidence Gate distingue:

- `healthy`
- `confirmed_product_failure`
- `qa_inconclusive`
- `qa_infrastructure`
- `warning`

Solo `confirmed_product_failure` con evidencia nueva correlacionada debe tratarse como fallo confirmado del producto.

Un `qa_inconclusive` o `qa_infrastructure` sigue bloqueando la certificación QA, pero debe repararse el harness en lugar de modificar producto sin evidencia.

## Estado conocido al 2026-10-04

En el último run documentado:

- build del APK Preview QA: success;
- proceso Android: vivo;
- fatales Android confirmados: 0;
- nuevos fallos confirmados de producto: 0;
- los smokes autenticados no llegaron a las assertions esperadas después del login;
- Visual AI no pudo certificarse por credencial Maestro Cloud;
- el verdict quedó no concluyente/infraestructura.

No “hacer verde” el workflow ignorando estos pasos. Corregir autenticación, assertions y credenciales del harness.

## Laboratorio de carga relacionado

El laboratorio no sustituye los smokes Maestro.

`express-load-lab` genera datos sintéticos con:

- `scope=sandbox|production`
- `channel=preview|production`
- `service_mode=mixed|car|motorcycle`

Iquique usa CLP y el modo Mixto crea Auto + Moto compatibles con los filtros reales de pasajero/conductor.

## Corrección 2026-10-06: geografía autoritativa del QA

El viaje sintético no puede usar coordenadas, moneda o servicio de una ciudad fija.

Regla vigente:

- el conductor QA se aprovisiona en una zona activa concreta;
- el seed consulta el `zone_id` real del conductor;
- pickup = centro operativo de esa zona;
- moneda = `service_zones.currency_code`;
- servicio = primer servicio habilitado y visible para pasajero + conductor en `zone_service_catalog`;
- el emulador recibe exactamente las mismas coordenadas guardadas en `driver-request-seed.json`.

Motivo: QA #736 intentó mover el conductor de Trinidad a Iquique y el trigger de cobertura rechazó correctamente el cambio con HTTP 400. Ese rojo se clasifica como infraestructura QA, no regresión de producto.



## 2026-10-06 · Límites de tiempo del harness

QA #741 no confirmó una regresión de producto. La base Preview 1.6.0+154 se resolvió correctamente, el smoke Android pasó y el backend terminó `healthy` con 0 fallos nuevos confirmados. El job fue cancelado por el límite global de 35 minutos mientras Maestro seguía esperando un flujo autenticado, por lo que nunca alcanzó a escribir `device-verdict.json`.

Corrección del harness:

- el job QA sube de 35 a 60 minutos para futuras ejecuciones;
- cada flujo Maestro obligatorio tiene además un timeout duro independiente;
- smoke: 180 s;
- pasajero autenticado: 240 s;
- conductor autenticado: 240 s;
- solicitud viva al conductor: 240 s;
- Visual AI: 180 s y sigue siendo evidencia advisory;
- si un flujo excede su tiempo, se conserva el código de salida, se escriben los artefactos/verdict y el Evidence Gate puede clasificarlo correctamente en vez de terminar por cancelación global.

Este ajuste es **solo infraestructura QA**. No cambia la APK +154 ni Producción.

---

## 2026-10-06 · QA obligatorio de Producción y viaje completo

La auditoría del fallo de arranque de Producción +158/+159 encontró cuatro huecos que quedan cerrados:

- Preview y Producción deben usar el mismo bootstrap de Supabase/auth (`lib/core/express_supabase_bootstrap.dart`);
- QA compila y arranca también `lib/mobile_main.dart` con package `com.express.usuario1`, no solo Preview;
- el smoke de Producción debe llegar a Login y bloquea si aparece `Express no pudo iniciar` / `E-START-AUTH`;
- el release gate no puede aprobar ni compilar Producción hasta que el workflow QA certifique exactamente `preview_build_id + SHA + versión + build`.

El viaje sintético obligatorio deja de terminar al recibir la solicitud. Ahora valida:

`request → oferta → selección → conductor en camino → conductor esperando → PIN → en progreso → completado → calificación pendiente pasajero → calificación pendiente conductor → dos ratings persistidos`.

Un fallo posterior a una preparación válida del viaje se clasifica como `confirmed_product_failure`; problemas de credenciales/provisión siguen siendo `qa_infrastructure`.

Solo un APK publicado como `preview-shorebird-v<version>-build<build>/app-release.apk` puede convertirse en Preview autoritativa del gate. Los APK genéricos `preview-android-...` son artefactos de diagnóstico y no pueden sustituir la base Shorebird.
