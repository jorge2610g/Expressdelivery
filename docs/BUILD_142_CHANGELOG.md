# Registro de cambios — Express Principal 1.6.3+142

**Registro vivo. Última actualización: 2026-10-21.** Todas las modificaciones de esta versión deben anotarse en este archivo *en el mismo PR #270*, con su SHA real, prueba y motivo. **Esta tabla distingue cambios hechos de decisiones propuestas.** No se considera completada la 142 hasta ejecutar QA del HEAD consolidado.

## Identidad y punto de recuperación
- Repositorio: `jorge2610g/Expressdelivery`.
- **Única rama de trabajo:** `work/express-single-app-1.6.3-build142`. Pull request: https://github.com/jorge2610g/Expressdelivery/pull/270 (draft).
- **Fuente 141:** `545b03339b69fc8b89f53f9aec43855772e404a5` (identificada por solicitud de build AAB; verificar su identidad contra `identity.json` firmado).
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

**Aclaración:** la actualización de documentos no implica que sus instrucciones ya hayan sido ejecutadas por Claude. Los únicos cambios nuevos al código/versión móvil verificados hasta este punto son el incremento de `pubspec.yaml`; **aún no hay código funcional divergente portado desde PR #262/#265 ni builds 142 nuevos**.

## Revisión de cambios previos: no duplicar
| Origen | Comparación / estado | Acción en 142 |
|---|---|---|
| PR #254 — base de app Android única | Contenido previo al SHA origen 141. | Ya heredado; no volver a fusionar. |
| PR #258 — reparaciones locales 141 | Ya integrado en rama oficial de la 141. | No duplicar. |
| PR #261 — fallo de flag flotante | HEAD ancestro de fuente publicada 141. | No duplicar. |
| PR #262 — candidato QA | `4f71b25` (324/324 tests + Kotlin/emulador según PR) es ancestro de la fuente 141; su HEAD `f484081` tiene otros cambios posteriores y diverge. | Comparar los *cambios adicionales* y probarlos en 142 antes de portar; no tratarlos como probados por tests antiguos. |
| PR #265 — barra flotante 30s/cancelaciones Realtime | HEAD `d1f382b`, divergente; PR declara solo verificaciones estáticas y QA Android pendiente. | Revisar compatibilidad de Kotlin/Dart y probar cancelación/caducidad/fondo antes de portar. |
| PR #266 — publicador AAB-only | Contiene procedimiento Play interna pero modalidad aislada AAB-only. | Reusar **solo** los controles seguros para la pista interna; la política actual exige APK + AAB mismo job, no dos apps. |
| PR #267/#268 — avisos Android y confirmación de publicación 141 | Cambios SQL/distribución diferentes al código móvil. | No ejecutar ni reaplicar migraciones; contrastar versión máxima de Play al publicar. |

## Trabajo pendiente: **NO HECHO**
1. Validar fuente exacta del AAB 141 publicado mediante `identity.json`/hash oficial y cotejar con SHA `545b033...`. No inferir del nombre de Release que coinciden.
2. Inspeccionar diferencias archivo por archivo contra HEAD de #262/#265 y, si son mejoras que siguen vigentes, integrarlas en ESTA rama con commits propios y tests; conservar la implementación más reciente de 141 donde haya conflictos.
3. Arreglar el procedimiento local de Flutter 3.47.5/Android `com.express.usuario1` usando scaffold, overlay nativo, permisos ZEGO, Firebase y registrant del pipeline oficial. Comprobar que VS Code puede iniciar con `flutter run -t lib/mobile_main.dart -d <EMULADOR> --debug`.
4. Ejecutar en el SHA **final** `flutter analyze`, `flutter test` completo, Kotlin/debug Android y QA de Taxi, Envíos, Delivery, llamadas, push, overlay, contexto por cuenta. Registrar fallas, correcciones y evidencia; no heredar sin más el PASS 324/324 del PR #262.
5. Adaptar los controles heredados 141 del workflow de compilación a un **job nuevo 142** con autorización vigente, fuente SHA exacta y `single-app-candidate-apk+aab` o el tipo realmente admitido; **no** reutilizar `.github/build-requests/android-141.json` ni el UUID 141.
6. Solo tras QA y autorización, firmar **un APK + un AAB** del mismo SHA, comprobar ambos hashes y firma, subirlos a una Release oficial, dejar APK descargable y comprobar aptitud del AAB para pista `qa`/`internal`. El flujo Play interno mantiene sus verificaciones/permisos; publicación en pista interna únicamente. No producción ni despliegues de backend.

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
