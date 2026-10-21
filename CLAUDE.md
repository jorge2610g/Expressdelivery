# CLAUDE.md — lectura obligatoria al entrar al proyecto Express Principal

> **Actualizado 21-10-2026.** Se ha preparado UNA rama de trabajo para la versión **Express 1.6.3+142**. Lee este archivo antes de programar en VS Code, de cambiar una rama o de compilar.

## Primeros enlaces (fuente de verdad)
1. [PR #270 — versión única 142](https://github.com/jorge2610g/Expressdelivery/pull/270): instrucciones del propietario y entrega de resultados.
2. [Guía de fuente 141 → 142, QA y distribución](docs/BUILD_142_UNIFIED_SOURCE_AND_EMULATORS.md).
3. [Registro cronológico de cambios, eliminaciones, pruebas y pendientes](docs/BUILD_142_CHANGELOG.md).
4. [AGENTS.md](AGENTS.md): reglas superiores de arquitectura, permisos y seguridad. No contradecirlas.

## Qué pide el propietario
**No trabajar sobre copias antiguas ni arrancar desde la rama `main` actual**, porque esta aún declara `1.6.2+140`. Recuperar y continuar **el código exacto de la 141 usada por el AAB oficial**, no modificar el archivo AAB binario. Consolidar aquí cambios probados posteriores para que todo sea UNA aplicación Android de Taxi, Envíos y Delivery cliente.

- **Rama única:** `work/express-single-app-1.6.3-build142`.
- **Base identificada:** `545b03339b69fc8b89f53f9aec43855772e404a5` (fuente del job AAB 141 según registro GitHub; cotejar `identity.json` de Release).
- **Versión objetivo:** `1.6.3+142`; **paquete:** `com.express.usuario1`; **entrypoint:** `lib/mobile_main.dart`.
- **Artefactos solicitados:** *un único job oficial APK + AAB del MISMO SHA*. APK y AAB firmados de la misma app oficial. No crear publicadores ni subir/promover a Play sin aprobación separada; no tocar datos de producción.
- **Estado actual:** solo rama + versionado + instrucciones/documentación. NO se ha confirmado integración de cambios divergentes, QA del HEAD final, compilación ni publicación de 142. No afirmar que ya están listos.

## Qué debes hacer al abrir VS Code
1. `git fetch origin`; `git switch work/express-single-app-1.6.3-build142`; `git pull --ff-only origin work/express-single-app-1.6.3-build142`. Antes de empezar: `git status --short`, `git rev-parse HEAD` y `grep '^version:' pubspec.yaml`. Si hay cambios locales, protegerlos antes de cambiar de rama; jamás sobrescribirlos sin inventario.
2. Revisar genealogía de #254, #258, #261, #262, #265, #266, #267, #268 frente al SHA 141. El commit validado `4f71b25` de #262 ya es ancestro del AAB 141; **NO volver a incorporarlo**. Las modificaciones adicionales del HEAD posterior de #262 y las de #265 **NO tienen el mismo nivel de pruebas documentado**; examinar y probar antes de integrar.
3. Preparar Flutter local con **3.47.5**, el scaffold Android y **overlay nativo** tal como `.github/workflows/build-android.yml`: la generación limpia de `android/` y aplicación de `.github/scripts/apply_floating_overlay.py` son parte del build. Verificar paquete, AndroidManifest, Gradle/plugins, permisos, firma/configuración Firebase sin publicar secretos.
4. Revalidar `flutter analyze`, `flutter test`, compilación Kotlin y arranque real con `flutter run -t lib/mobile_main.dart -d <EMULADOR> --debug`. Dart admite Hot Reload; cambios Kotlin/manifiesto requieren reconstrucción debug. APK release solo sirve para instalar/probar el candidato ya congelado, **no para editarlo**.
5. Al finalizar QA, preparar el pipeline original **`single-app-candidate-apk+aab`** usando **un NUEVO job 142** autorizado y SHA final verificado. No reutilizar UUID, source_sha ni request 141. Guardar APK, AAB e `identity.json` vinculados; comprobar hash/firma/versión. No crear publicadores ni promocionar a Play sin aprobación separada.

## Documentación obligatoria por cada commit
- En `docs/BUILD_142_CHANGELOG.md`: **archivo/ruta, estado añadido/modificado/eliminado, antes → después, motivo, SHA, prueba real, impacto, pendiente**. Si quitas código, describe exactamente cuál fue retirado, por qué y qué lo reemplaza. Si no quitaste nada, anota «Sin eliminaciones».
- Actualiza el cuerpo/comentarios de [PR #270](https://github.com/jorge2610g/Expressdelivery/pull/270) con resultados y dificultades, **en el mismo PR**. No abrir 142 paralelas ni mezclar propuestas SQL con código listo.
- Cada prueba debe indicar **SHA real** sobre el que se ejecutó, comandos y resultados. Un test PASS heredado de la 141 no equivale a PASS en la nueva 142.
- Mantener `main`, Producción, migraciones y Edge Functions sin cambios salvo autorización separada.

**Tu primer mensaje al PR debe señalar qué SHA local abriste y la diferencia real con el commit base 141.** No declararse listo hasta probar el flujo completo y presentar los artefactos oficiales.
