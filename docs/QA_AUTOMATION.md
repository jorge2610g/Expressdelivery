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
