# CLAUDE.md — Express Principal

> **Actualizado 2026-11-12.** Candidata en curso: **1.6.9+167** (commit `7c3f586f`, solicitud en `main` y build `ready` con firma de producción en la tabla de builds). Build anterior: **1.6.9+166** (`ready`, QA del propietario pendiente). El gate de Supabase registra `production_store_build_number` 164 y `next_production_build_number` 168; la versión de Producción en Play no se confirmó desde el repositorio (ver Pendientes). Estado operativo completo en [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md), sección «Estado vigente — 2026-11-12».

## Fuente de estado y reglas

1. Lee [AGENTS.md](AGENTS.md) antes de modificar arquitectura, seguridad, datos o release.
2. Usa [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md) como estado operativo; confirma GitHub, Supabase y Google Play antes de afirmar que una publicación sigue vigente.
3. Los documentos [BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md](docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md) y [BUILD_142_CHANGELOG.md](docs/BUILD_142_CHANGELOG.md) son históricos. No describen el trabajo actual.
4. Conserva Preview y Producción aislados por cuenta. No publiques, promociones, marques una actualización crítica ni envíes avisos sin orden explícita del propietario.

## Android

- Paquete oficial: `com.express.usuario1`; entrypoint: `lib/mobile_main.dart`.
- Producción de Play: **1.6.4+156**. Prueba interna: **1.6.8+160** (QA aprobado el 02-11). Sin promoción a Producción autorizada.
- Candidata en curso: **1.6.9+167** (commit `7c3f586f`, `build_jobs` en `ready`, firma de producción). Versión (`pubspec.yaml`) y build (`.github/build-requests/android-internal.json`) suben juntos. Solo para Prueba interna. Anteriores: 1.6.9+166 (`ready`, QA pendiente), 165 y 164.
- Los builds 153, 154, 155, 157 y 158 son históricos. No los uses como referencia de estado.
- La demo web Express Moto no forma parte de la app Android.
- El GPS no está validado en teléfonos reales. No declares resuelto el GPS hasta probar movimiento real en ambos teléfonos.
- No reutilices UUID de build ni cambies la fuente de una candidata ya compilada. La secuencia oficial verifica SHA, firma, identidad, Google Play Internal y artefactos antes de marcar el build listo.

## Web

- Web oficial de pasajeros y conductores en Prueba: `https://expressviajes.online/`, commit `ef41a085` o posterior.
- Incluye: cobro con QR dentro de la tarjeta del pasajero (sin popup), carga del QR solo si la imagen existe, tarjeta que se entera del cobro en segundos, y modo conductor en la web solo para cuentas de Prueba (`ExpressRuntimeChannel.webDriverModeAllowed`).
- Las pruebas manuales de web quedaron cerradas por el propietario el 02-11.
- Las cuentas de Producción en la web son solo pasajero. El servidor todavía no bloquea acciones de conductor para esas cuentas; ver Pendientes.

## Base de datos (Supabase `zgpijrznvaskgcmauwxx`)

- Conductor ocupado: migración `busy_driver_offer_guard` aplicada el 02-11 (`20261102200000_busy_driver_offer_guard.sql` en el repositorio). Impide ofertas y selecciones para un conductor con viaje activo.
- Migraciones aplicadas no se editan. Las nuevas se crean como archivos nuevos.
- Aplicadas el 2026-11-12: `20261112120000_driver_request_passenger_summary`, `20261112130000_phone_country_for_point` y `20261112140000_revoke_publish_verified_play_build_public_execute` (quita la ejecución de `anon` y `authenticated` a `publish_verified_play_build`).
- Aplicada el 2026-11-12: `20261015000500_generic_driver_document_photo_review_v2` (con la corrección del `CASE` dentro de `IF` del PR #430). El panel de Adminexpress ya la puede llamar. QA de RLS, disparadores y canal pendiente.
- Sin aplicar: `20261023120000_driver_web_registration_approval_email`. Necesita el secreto de Vault `driver_approval_service_role_key`; aplicarla sin él bloquea todas las aprobaciones de conductores.

## Pendientes conocidos

- Promoción de 1.6.8+160, 1.6.9+161, 1.6.9+163, 1.6.9+164, 1.6.9+166 o 1.6.9+167 a Producción: no autorizada. Se hará después de la prueba interna y con orden del propietario.
- El servidor todavía no bloquea acciones de conductor para cuentas de Producción desde la web. Requiere migración aparte con autorización.
- La configuración de prioridad de conductores copia producción en preview. Decidir si es intencional.
- PR #373 (propuesta de rediseño de inicio): abierto, sin decisión del propietario.
- Migración `busy_driver_offer_guard`: el nombre coincide en Supabase. La versión registrada es `20261102190817` y el archivo del repositorio es `20261102200000`. Desajuste solo de registro; no se renombra.
- Ofertas pendientes al desconectarse: no comprobado en el código. Las ofertas expiran por tiempo.
- GPS, pruebas de cupones, redes sociales, grupos de suscripción, avisos programados y billetera: cerradas por el propietario el 07-11 (confirmación del propietario, sin verificación técnica adicional).
- `Express_Repartidor`: borrado manual en GitHub por el propietario (confirmar que quedó hecho).
- Promoción de la candidata 1.6.9+167 a Producción: no autorizada.
- Build 166 y 167: confirmar en Play Console Prueba interna y el QA del propietario antes de promover.
- `claude/cool-faraday-yhh09s`: obsoleta. Su fix de notificación del pasajero ya está en `main` (`driverBackgroundTracking`); no borrada.
- Cuenta `review-express-62e0@cabgo.app`: borrado pendiente de confirmación en Supabase.
- Advisors de seguridad: 39 funciones ejecutables por `anon` (revisadas 22, la mayoría valida usuario); faltan 17 por revisar.
- Mantén este archivo y el handoff sincronizados con el estado verificado. Separa lo comprobado en CI de lo comprobado en teléfonos.
