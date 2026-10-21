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
| 2026-10-21 | `d0d0c8c79831450450594e94bc7ca7675482e9aa` | `.github/workflows/play-internal.yml`, `scripts/play_internal.py`, `docs/GOOGLE_PLAY_INTERNAL_TESTING.md` | **Añadidos** | Publicador Play interno que consume solo la pareja firmada del Release 142, compara SHA/identidad, rechaza versionCode ocupado y limita destino a `qa`/`internal`; `publish` requiere confirmación explícita. Añade instrucciones de operación. | Sin eliminaciones | `py_compile`, self-test de identidad/hashes/pistas/confirmación, parse YAML: PASS. Sin llamadas a Play ni publicación en este commit. |
| 2026-10-21 | `1bb004b6d193190a984815a1eb890c5e0802e27c` | `docs/BUILD_142_CHANGELOG.md`, `docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md` | **Modificados** | Registra el publicador recién añadido, corrige el estado real de publicación interna y documenta el estado de autorización/versión del backend. | Sin eliminaciones | `git diff --check`; los pasos de publicación aún no se ejecutaron porque no existe Release 142 firmada. |
| 2026-10-21 | `e9e6cb4c4fe71ed6cd31c54977c86011034fb6b0` | `.github/workflows/play-internal.yml`, `scripts/play_internal.py`, `docs/GOOGLE_PLAY_INTERNAL_TESTING.md`, `docs/BUILD_142_CHANGELOG.md` | **Modificados** | Actualiza `google-auth` 2.38.0 → 2.62.0 y `requests` 2.32.3 → 2.34.2; conserva las releases/versionCodes existentes de la pista al añadir 142 y registra el cambio. | Sin eliminaciones | `py_compile`, self-test de retención de códigos y confirmación, parse YAML y bash syntax: PASS. La forma de track se verifica contra el contrato actual de Google Play; aún no hay llamada real ni publicación. |
| 2026-10-21 | `2b242b43a81237017ecd9848235b67ace7c2334a` | `docs/GOOGLE_PLAY_INTERNAL_TESTING.md`, `docs/BUILD_142_CHANGELOG.md` | **Modificados** | Documenta el dispatch del workflow oficial de build después de que el administrador cree el job autorizado 142. | Sin eliminaciones | `git diff --check`; no se ha ejecutado el workflow porque no hay job UUID 142. |
| 2026-10-21 | _este commit_ | `docs/BUILD_142_CHANGELOG.md` | **Modificado** | Fija el SHA de las instrucciones de dispatch y registra el estado del gate administrativo. | Sin eliminaciones | `git diff --check`. |
| 2026-10-21 | `9324e1ff41be2be7ae0513a14e0f1de8a75e600a` | `.github/workflows/play-internal.yml`, `scripts/play_internal.py`, `docs/GOOGLE_PLAY_INTERNAL_TESTING.md`, `CLAUDE.md`, `docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md` | **Eliminados / modificados** | Se retira el publicador automatizado de Play y sus instrucciones porque la regla vigente prohíbe añadir publicadores. Play requiere aprobación separada; no se incorpora otro flujo de publicación. La APK+AAB candidata oficial solo puede generarse mediante el workflow único y el job administrativo autorizado. No cambia Taxi, Envíos, Delivery ni ZEGO. | Eliminados workflow, script y guía del publicador; actualizadas referencias contradictorias. | `git diff --check`; comprobación de referencias y contrato de app única PASS. Sin llamadas ni publicaciones a Play. |

**Aclaración:** no se portó lógica funcional de #262/#265 porque el delta móvil de #262 es comentario y su delta de backend depende de cambios de Supabase no incluidos en esta integración; #265 revierte cobertura y comportamiento ya incluidos en 141. El único cambio nuevo en la app es la prueba de versión. El publicador de Play que se había añadido fue retirado por la regla vigente; la promoción a Play requiere aprobación separada. No hay APK/AAB release 142 nuevos.

**Actualización de distribución solicitada por el propietario:** se reemplaza esa decisión anterior para 142: la confirmación directa autoriza Google Play **Pruebas internas**. El único workflow Android construye APK+AAB, crea la Release descargable y carga el mismo AAB a `internal`. Si QA pasa, esa misma AAB, versión, SHA y hashes se promueven a Producción por el gate administrativo, sin recompilar; la ejecución actual no promueve a Producción. Esta actualización no crea otra aplicación ni otro workflow.

## Revisión de cambios previos: no duplicar
| Origen | Comparación / estado | Acción en 142 |
|---|---|---|
| PR #254 — base de app Android única | Contenido previo al SHA origen 141. | Ya heredado; no volver a fusionar. |
| PR #258 — reparaciones locales 141 | Ya integrado en rama oficial de la 141. | No duplicar. |
| PR #261 — fallo de flag flotante | HEAD ancestro de fuente publicada 141. | No duplicar. |
| PR #262 — candidato QA | `4f71b25` (324/324 tests + Kotlin/emulador según PR) es ancestro de la fuente 141; HEAD `f484081` tiene cambios posteriores del worker de push, no una corrección móvil pendiente. | No duplicar código móvil; no modificar Supabase sin una orden específica. |
| PR #265 — barra flotante 30s/cancelaciones Realtime | HEAD `d1f382b`, divergente y con regresiones frente a la 141. | No portar la regresión ni reemplazar el contrato de 141. |
| PR #266 — publicador AAB-only | Contiene controles de API para pista interna, pero su build aislado es AAB-only. | No se importa su publicador ni se crea uno nuevo; la única candidata oficial permanece en el workflow de build con autorización administrativa. |
| PR #267/#268 — avisos Android y confirmación de publicación 141 | Cambios SQL/distribución diferentes al código móvil. | No ejecutar ni reaplicar migraciones; contrastar versión máxima de Play al publicar. |

## Estado verificado y pendientes
1. **Completado:** se comprobó el `identity.json` y el SHA-256 del AAB de la Release oficial 141; coincide con la fuente 141 documentada.
2. **Completado:** diffs archivo por archivo de 141 a HEAD de #262 y #265. No hay corrección móvil adicional vigente que falte en 142 y sea segura de integrar sin backend; #265 deshace cambios ya incorporados. No se duplicó ni se modificó Supabase.
3. **Completado localmente:** Flutter 3.47.5; scaffold Android nuevo en `android/`, overlay nativo aplicado mediante `.github/scripts/apply_floating_overlay.py`, Firebase y plugin registrant regenerados. El pipeline oficial vuelve a crear ese scaffold; `android/` local es generado y no se agrega al PR.
4. **Completado parcialmente:** Flutter test completo 392/392 PASS; pruebas focalizadas overlay 24/24 PASS; prueba release gate 2/2 PASS. `flutter analyze` completo mantiene advertencias/infos heredadas y sale con código 1; el análisis del conjunto de archivos críticos del workflow pasa con `--no-fatal-warnings --no-fatal-infos`. `flutter run -t lib/mobile_main.dart -d emulator-5554 --debug` y `emulator-5556` arrancaron con `versionCode=142`; en Pixel se verificó visualmente el panel del conductor y hot reload/restart. La primera ejecución local necesitó restaurar el PNG canónico con `restore_branding_asset.py`; después del reinicio no quedó excepción de imagen.
5. **Pendiente de QA real:** no se generó ni canceló una oferta backend; por eso no se certifica de punta a punta push vs overlay, cancelación/expiración en ambos roles ni llamadas. No se ingresaron órdenes en producción.
6. **Pendiente para ejecutar la release:** el baseline productivo de Google Play es 141 y el siguiente código permitido es 142. El conector Supabase disponible devuelve `auth.uid() = NULL` y `public.is_admin() = false`; por ello no se puede crear el nuevo job mediante el RPC administrativo desde esta sesión y no se omitió ese control. El workflow ahora preflighta el secreto de Play, el acceso al paquete y la disponibilidad del versionCode, y sube solo al track `internal`; aún no existe Release APK+AAB 142 ni se ha cargado nada. No reutilizar el job 141.

## Cambio de esta iteración

| Fecha | SHA | Archivo(s) | Operación | Antes → después / motivo | Impacto | Pruebas en este SHA | Estado |
|---|---|---|---|---|---|---|---|
| 2026-10-21 | `0a4cb8cf759570ea239d114c0f6394f270c2d45c` | `.github/workflows/build-android.yml`, `scripts/play_internal_upload.py`, `.github/workflows/validate-single-app-release-gate.yml`, `CLAUDE.md`, `docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md` | Modificados / añadido | El dispatch oficial acepta solo `single-app-candidate-apk+aab`; valida Play Internal y `versionCode` antes del build, luego vincula hash/SHA/tag, publica la Release y sube AAB solo a `internal` en la misma ejecución. Actualiza las instrucciones que anteriormente prohibían la carga interna. | Sin cambios a Taxi, Envíos, Delivery, ZEGO, Supabase ni Producción. | `python3 -m py_compile scripts/play_internal_upload.py`, `python3 scripts/play_internal_upload.py --mode check --self-test`, `python3 .github/scripts/check_single_app_contract.py`, Ruby YAML parse de ambos workflows y `git diff --check`: PASS sobre el contenido del commit. No hay job administrativo nuevo para ejecutar el build. | Implementación validada localmente; pendiente push/ejecución. Sin APK/AAB ni publicación aún. |
| 2026-10-21 | pendiente de commit | `docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md`, `docs/BUILD_142_CHANGELOG.md` | Modificados | Aclara el destino autorizado tras QA: Producción debe promover el mismo AAB interno con el mismo SHA/hash/versionCode, sin recompilar; el run actual solo publica a Internal. | Ninguna. | `git diff --check`: PASS; PR #270 actualizado. | Documentación sincronizada; pendiente push. |

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
