# CLAUDE.md — Express Principal

> **Actualizado 2026-11-01.** Google Play Producción: **1.6.4+156** (observado y confirmado por el propietario). Prueba interna: **1.6.7+159** (candidata subida el 02-11, QA manual en teléfono pendiente del propietario). Siguiente candidata: **1.6.8+160** (sube versión y build a la vez), todavía no preparada. Estado completo en [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md), sección «Estado vigente».

## Fuente de estado y reglas

1. Lee [AGENTS.md](AGENTS.md) antes de modificar arquitectura, seguridad, datos o release.
2. Usa [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md) como estado operativo; confirma GitHub, Supabase y Google Play antes de afirmar que una publicación sigue vigente.
3. Los documentos [BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md](docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md) y [BUILD_142_CHANGELOG.md](docs/BUILD_142_CHANGELOG.md) son históricos. No describen el trabajo actual.
4. Conserva Preview y Producción aislados por cuenta. No publiques, promociones, marques una actualización crítica ni envíes avisos sin orden explícita del propietario.

## Android

- Paquete oficial: `com.express.usuario1`; entrypoint: `lib/mobile_main.dart`.
- Producción de Play: **1.6.4+156** (observada el 01-11). El registro `app_release_gate` aún dice 152; reconciliar cuando el propietario lo ordene.
- Prueba interna actual: **1.6.8+160** (commit `9615a918`), subido a Internal el 02-11. QA manual en teléfono aprobado por el propietario el 02-11. Sin promoción a Producción autorizada.
- Siguiente candidata: **1.6.9+161**. Versión y build suben juntos. Sin preparar hasta tener mejora revisada y orden del propietario.
- Los builds 153, 154, 155 y 157 son históricos. No los uses como referencia de estado.
- La demo web Express Moto no forma parte de la app Android.
- No declares resuelto el GPS hasta probar movimiento real en ambos teléfonos.
- No reutilices UUID de build ni cambies la fuente de una candidata ya compilada. La secuencia oficial verifica SHA, firma, identidad, Google Play Internal y artefactos antes de marcar el build listo.

## Web

- La primera suscripción Realtime web se publicó en `76eba26ffbbda767fa441d4c412ebcc56ff65fe6`; la auditoría encontró que leía el broadcast como si viniera envuelto en `payload`.
- La corrección consume el mapa recibido directamente y se publicó en `00c05d2fff20a6130a29ab7d1c65f192980e1e4b`, Pages run [40899895071](https://github.com/jorge2610g/Expressdelivery/actions/runs/40899895071). Análisis, pruebas, builds y despliegue pasaron. Falta probar el marcador durante un viaje real.

## Pendientes conocidos

- La selección de dirección mediante pin sigue sin reproducirse ni confirmarse resuelta.
- El mapa GPS en vivo del pasajero está corregido en la web; Android necesita un nuevo Internal candidate porque el build 153 no contiene el arreglo del callback.
- El PR [#137 de Adminexpress](https://github.com/jorge2610g/Adminexpress/pull/137) continúa abierto como borrador; revisar y probar los permisos por módulo y la acción de borrado.
- La validación en dispositivos de GPS y de la notificación del conductor está pendiente.
- Mantén este archivo y el handoff sincronizados con el estado verificado. Separa lo comprobado en CI de lo comprobado en teléfonos.
