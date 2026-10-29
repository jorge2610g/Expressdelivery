# CLAUDE.md — Express Principal

> **Actualizado 2026-10-29.** Producción de Google Play sigue en **1.6.4+152**. La candidata firmada **1.6.4+153** está en la pista **Internal** para prueba manual; todavía no tiene QA de teléfono ni autorización para pasar a Producción.

## Fuente de estado y reglas

1. Lee [AGENTS.md](AGENTS.md) antes de modificar arquitectura, seguridad, datos o release.
2. Usa [CURRENT_STATE_HANDOFF_20261027.md](docs/CURRENT_STATE_HANDOFF_20261027.md) como estado operativo; confirma GitHub, Supabase y Google Play antes de afirmar que una publicación sigue vigente.
3. Los documentos [BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md](docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md) y [BUILD_142_CHANGELOG.md](docs/BUILD_142_CHANGELOG.md) son históricos. No describen el trabajo actual.
4. Conserva Preview y Producción aislados por cuenta. No publiques, promociones, marques una actualización crítica ni envíes avisos sin orden explícita del propietario.

## Android

- Paquete oficial: `com.express.usuario1`; entrypoint: `lib/mobile_main.dart`.
- Build Internal actual: **1.6.4+153**, SHA `4a6f04f78c09bf6c8fa53abded37693cfef05337`, basado en el código publicado como build 152, `89f253c42e79942c1d1c6785c7a7297046f75cbe`.
- Build 153 incluye actualización GPS en vivo para el mapa del conductor y pasajero y limita el aviso persistente de ubicación en segundo plano al conductor.
- El build 153 no incluye la demo web Express Moto. Producción de Play permanece en 152.
- La prueba manual de navegación en Internal aún está pendiente. No declares resuelto el GPS hasta probar movimiento real en ambos teléfonos.
- No reutilices UUID de build ni cambies la fuente de una candidata ya compilada. La secuencia oficial verifica SHA, firma, identidad, Google Play Internal y artefactos antes de marcar el build listo.

## Web

- El mapa web del pasajero ahora escucha la ubicación del conductor por Supabase Realtime y actualiza el marcador sin refresco manual.
- Despliegue verificado: commit `76eba26ffbbda767fa441d4c412ebcc56ff65fe6`, GitHub Actions run [40882689331](https://github.com/jorge2610g/Expressdelivery/actions/runs/40882689331), sitio [expressviajes.online](https://expressviajes.online/).
- El despliegue completó análisis, pruebas, build y publicación. La prueba funcional de un viaje con dos teléfonos aún debe hacerla el propietario.

## Pendientes conocidos

- La selección de dirección mediante pin sigue sin reproducirse ni confirmarse resuelta.
- El PR [#137 de Adminexpress](https://github.com/jorge2610g/Adminexpress/pull/137) continúa abierto como borrador; revisar y probar los permisos por módulo y la acción de borrado.
- La validación en dispositivos de GPS y de la notificación del conductor está pendiente.
- Mantén este archivo y el handoff sincronizados con el estado verificado. Separa lo comprobado en CI de lo comprobado en teléfonos.
