# CLAUDE.md — Express Principal

> **Actualizado 2026-11-02.** Google Play Producción: **1.6.4+156**. Prueba interna: **1.6.8+160** (QA aprobado por el propietario el 02-11). Candidata en curso: **1.6.9+161** (solicitud de build enviada el 02-11; el estado real se confirma en el workflow y en Google Play Internal). Estado operativo completo en [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md), sección «Estado vigente — 2026-11-02».

## Fuente de estado y reglas

1. Lee [AGENTS.md](AGENTS.md) antes de modificar arquitectura, seguridad, datos o release.
2. Usa [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md) como estado operativo; confirma GitHub, Supabase y Google Play antes de afirmar que una publicación sigue vigente.
3. Los documentos [BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md](docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md) y [BUILD_142_CHANGELOG.md](docs/BUILD_142_CHANGELOG.md) son históricos. No describen el trabajo actual.
4. Conserva Preview y Producción aislados por cuenta. No publiques, promociones, marques una actualización crítica ni envíes avisos sin orden explícita del propietario.

## Android

- Paquete oficial: `com.express.usuario1`; entrypoint: `lib/mobile_main.dart`.
- Producción de Play: **1.6.4+156**. Prueba interna: **1.6.8+160** (QA aprobado el 02-11). Sin promoción a Producción autorizada.
- Candidata en curso: **1.6.9+161**. Versión (`pubspec.yaml`) y build (`.github/build-requests/android-internal.json`) suben juntos. Solo para Prueba interna.
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

## Pendientes conocidos

- Promoción de 1.6.8+160 o 1.6.9+161 a Producción: no autorizada.
- El servidor todavía no bloquea acciones de conductor para cuentas de Producción desde la web. Requiere migración aparte con autorización.
- La configuración de prioridad de conductores copia producción en preview. Decidir si es intencional.
- Verificar el nombre y la versión de la migración `busy_driver_offer_guard` en el registro de migraciones de Supabase.
- Verificar si las ofertas pendientes de un conductor se cancelan al desconectarse.
- GPS validado en dos teléfonos reales: pendiente.
- `Express_Repartidor`: borrado manual en GitHub por el propietario.
- Mantén este archivo y el handoff sincronizados con el estado verificado. Separa lo comprobado en CI de lo comprobado en teléfonos.
