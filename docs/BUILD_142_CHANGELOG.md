# Registro de cambios — Express Principal 1.6.3+142

**Registro vivo. Última actualización: 2026-10-21.** Todas las modificaciones de esta versión deben anotarse en este archivo *en el mismo PR #270*, con su SHA real, prueba y motivo. **Esta tabla distingue cambios hechos de decisiones propuestas.** No se considera completada la 142 hasta ejecutar QA del HEAD consolidado.

## Identidad y punto de recuperación
- Repositorio: `jorge2610g/Expressdelivery`.
- **Única rama de trabajo:** `work/express-single-app-1.6.3-build142`. Pull request: https://github.com/jorge2610g/Expressdelivery/pull/270 (draft).
- **Fuente 141:** `545b03339b69fc8b89f53f9aec43855772e404a5`, confirmada con el `identity.json` de la Release oficial 141: paquete `com.express.usuario1`, versión `1.6.3+141`, SHA fuente coincidente y AAB SHA-256 `505364b1baa29c91cb5616b9d8f9f73173352836eaf31f4559a9f73c45278843` (job `39192098858`).
- Identificador Android **invariable**: `com.express.usuario1`; arranque: `lib/mobile_main.dart`; configuración por cuenta y backend, no por APK separadas.
- `versionName`: `1.6.3`; `versionCode`: `142`.
- **Entrega solicitada:** un solo trabajo autorizado, dos artefactos del **mismo commit y versión**: APK release firmado, descargable para QA, y AAB release firmado, destinado solo a **Google Play Pruebas internas**. Nunca Producción de Play por defecto. Guardar también `identity.json`, URL y SHA-256 de ambos.
- El APK/AAB no es código fuente editable: VS Code + Claude trabajan en la rama; los emuladores iterativos usan `flutter run --debug` y, para cambios nativos, reconstrucción debug.
- Sin cambio de `main`, despliegue Supabase, modificación de producción ni nueva app Preview a esta fecha.

## Registro de cambios hechos y confirmados
| Fecha | SHA/Referencia | Archivo(s) | Estado | Antes → después / motivo | Eliminaciones | Pruebas y evidencia |
|---|---|---|---|---|---|---|
| 2026-10-21 | `545b03339b69fc8b89f53f9aec43855772e404a5` | Fuente de la 141 | Base conservada (no cambio nuevo) | Punto de origen de la candidata 142; conserva la lógica y recursos del AAB anterior. | Ninguna | PR #268 informa Play production 141; confirmar con `identity.json` de Release. |
| 2026-10-21 | `74bc53f03c139f48c5353486875688e44904483e` | `pubspec.yaml` | **Modificado** | `version: 1.6.3+141` → `version: 1.6.3+142`. Prepara la numeración para la misma app. | Ninguna | Contenido de `pubspec.yaml` leído en la nueva rama; NO prueba compilación. |
| 2026-10-21 | `97a78229facd92de8d4f911352954d356ec7c034` | `docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md` | **Añadido** | Guía de ramas, SHA de origen, QA/emuladores y controles de release. | Ninguna | Archivo guardado en GitHub en la rama 142; no prueba de app. |
| 2026-10-21 | `efc72f3c90a0ba0b18afc5fde9928277bfc74e7f` | `docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md` | **Modificado** | Sustituye la intención de AAB-only por **APK descargable + AAB para Play interna** desde un mismo job/commit, con bitácora obligatoria. | Ninguna | Actualización confirmada en GitHub. |
| 2026-10-21 | `a2eb58e2aeae2ffb8147ffacb0aa7a9779602604` | `CLAUDE.md` | **Añadido** | Instrucciones en raíz para que Claude encuentre **la rama 142** y no retorne a `main` 140 ni a versiones locales viejas; enlaces a PR #270, guía, bitácora. | Ninguna | Archivo guardado y leído desde GitHub. |
| 2026-10-21 | _este commit_ | `docs/BUILD_142_CHANGELOG.md` | **Añadido** | Registra los cambios reales y pendientes con trazabilidad para otros agentes. | Ninguna | La creación solo acredita documentación, no compilación. |
| 2026-10-21 | `4ba5220f51856b1d93b40ac4b7e0c2b637f55938` | `test/android_release_approval_gate_test.dart` | **Modificado** | La prueba de versión dejó de esperar `1.6.3+141` y ahora verifica la candidata `1.6.3+142`; la identidad de release sigue fijada a una autorización explícita. | Ninguna | Prueba específica: 2/2 PASS; suite Flutter completa: 392/392 PASS sobre el mismo contenido de trabajo. |

**Aclaración:** no se portó lógica funcional de #262/#265 porque el delta móvil de #262 es comentario y su delta de backend depende de cambios de Supabase no autorizados por esta orden; #265 revierte cobertura y comportamiento ya incluidos en 141. El único cambio de código nuevo es la prueba de versión anterior. No hay APK/AAB release 142 nuevos.

## Revisión de cambios previos: no duplicar
| Origen | Comparación / estado | Acción en 142 |
|---|---|---|
| PR #254 — base de app Android única | Contenido previo al SHA origen 141. | Ya heredado; no volver a fusionar. |
| PR #258 — reparaciones locales 141 | Ya integrado en rama oficial de la 141. | No duplicar. |
| PR #261 — fallo de flag flotante | HEAD ancestro de fuente publicada 141. | No duplicar. |
| PR #262 — candidato QA | `4f71b25` (324/324 tests + Kotlin/emulador según PR) es ancestro de la fuente 141; HEAD `f484081` tiene cambios posteriores del worker de push, no una corrección móvil pendiente. | No duplicar código móvil; no modificar Supabase sin una orden específica. |
| PR #265 — barra flotante 30s/cancelaciones Realtime | HEAD `d1f382b`, divergente y con regresiones frente a la 141. | No portar la regresión ni reemplazar el contrato de 141. |
| PR #266 — publicador AAB-only | Contiene procedimiento Play interna pero modalidad aislada AAB-only. | Reusar **solo** los controles seguros para la pista interna; la política actual exige APK + AAB mismo job, no dos apps. |
| PR #267/#268 — avisos Android y confirmación de publicación 141 | Cambios SQL/distribución diferentes al código móvil. | No ejecutar ni reaplicar migraciones; contrastar versión máxima de Play al publicar. |

## Estado verificado y pendientes
1. **Completado:** se comprobó el `identity.json` y el SHA-256 del AAB de la Release oficial 141; coincide con la fuente 141 documentada.
2. **Completado:** diffs archivo por archivo de 141 a HEAD de #262 y #265. No hay corrección móvil adicional vigente que falte en 142 y sea segura de integrar sin backend; #265 deshace cambios ya incorporados. No se duplicó ni se modificó Supabase.
3. **Completado localmente:** Flutter 3.47.5; scaffold Android nuevo en `android/`, overlay nativo aplicado mediante `.github/scripts/apply_floating_overlay.py`, Firebase y plugin registrant regenerados. El pipeline oficial vuelve a crear ese scaffold; `android/` local es generado y no se agrega al PR.
4. **Completado parcialmente:** Flutter test completo 392/392 PASS; pruebas focalizadas overlay 24/24 PASS; prueba release gate 2/2 PASS. `flutter analyze` completo mantiene advertencias/infos heredadas y sale con código 1; el análisis del conjunto de archivos críticos del workflow pasa con `--no-fatal-warnings --no-fatal-infos`. `flutter run -t lib/mobile_main.dart -d emulator-5554 --debug` y `emulator-5556` arrancaron con `versionCode=142`; en Pixel se verificó visualmente el panel del conductor y hot reload/restart. La primera ejecución local necesitó restaurar el PNG canónico con `restore_branding_asset.py`; después del reinicio no quedó excepción de imagen.
5. **Pendiente de QA real:** no se generó ni canceló una oferta backend; por eso no se certifica de punta a punta push vs overlay, cancelación/expiración en ambos roles ni llamadas. No se ingresaron órdenes en producción.
6. **Bloqueado:** el job oficial nuevo requiere crear una fila candidata con autorización admin en Supabase, operación que esta tarea prohíbe expresamente. El workflow de build acepta APK+AAB en un job y los sube a GitHub Release, pero no se encontró `.github/workflows/play-internal.yml` en esta rama y no hay paso de publicación a Play configurado. Por ello aún no hay APK/AAB de release 142, identidad/hashes oficiales ni envío a pruebas internas. No se reutilizó el job 141 ni se publicó a producción.

## Plantilla que Claude debe completar en cada modificación posterior
```text
Fecha:
SHA commit:
Archivo/ruta:
Operación: añadido / modificado / eliminado
Antes:
Después:
Por qué:
Impacto (Taxi / Envíos / Delivery / ZEGO / backend):
Pruebas ejecutadas EN ESTE SHA y resultado:
Estado: implementado / probado / bloqueado
Pendiente:
```

**REGLA:** Cuando una ruta sea eliminada, escribir «eliminado» y detallar qué reemplaza su función. Si no hubo eliminaciones, escribir explícitamente «Sin eliminaciones». No borrar este historial al consolidar ramas.
