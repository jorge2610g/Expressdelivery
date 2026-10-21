# Express Principal 1.6.3+142 — fuente única y trazabilidad

Estado: **candidato de integración, no AAB/APK compilado ni publicación Play**. Orden del propietario: consolidar los cambios ya realizados y probados y devolver a Claude un flujo normal VS Code/Flutter/emuladores; no mantener versiones paralelas.

## Punto de partida verificable
- Aplicación Android **única**: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Fuente elegida: `545b03339b69fc8b89f53f9aec43855772e404a5`; verificada contra el `identity.json` de la Release oficial 141 (mismo SHA, paquete `com.express.usuario1`, versión 1.6.3+141; AAB SHA-256 `505364b1baa29c91cb5616b9d8f9f73173352836eaf31f4559a9f73c45278843`).
- Google Play 141: el PR #268 indica que el canal production publicó `versionCode=141` y un AAB oficial asociado al job `470dc53d-eeef-4acd-bbf9-b226344c043b`. La verificación de Play figura en ese PR; **este documento no es una nueva comprobación de Play Console**.
- Este candidato parte de la fuente 141, **no de main** (que seguía declarando `1.6.2+140`) ni de un checkout local antiguo.
- Versión preparada: `1.6.3+142`. Cambiarla no compila ni publica ningún artefacto.

## Decisión vigente de distribución (21-10-2026)
- Se usa el flujo oficial conjunto APK + AAB, no un job AAB-only ni otra app. **La misma ejecución** del workflow oficial `build-android.yml` valida acceso a Play y disponibilidad del versionCode, genera ambos artefactos del mismo SHA, crea la Release descargable y sube ese AAB solo a la pista `internal` tras la confirmación `AUTORIZO APK+AAB PRUEBAS INTERNAS`.
- Un solo paquete `com.express.usuario1`, una sola `versionName=1.6.3`, un solo `versionCode=142`, mismos recursos Android/Firebase/firma y un `identity.json` vinculante. Verificar el SHA-256 **de cada archivo** y que los dos provengan del mismo job/commit.
- El APK oficial sirve para probar la versión candidata exacta en emuladores/dispositivos compatibles; **Claude debe editar el código de ESTA rama**, no intentar modificar APK o AAB compilados. Usar `flutter run -t lib/mobile_main.dart --debug` para iterar con Hot Reload y compilar la pareja APK+AAB **una vez validado el SHA final**. Un APK de release normalmente no permite Hot Reload; no confundir ambos usos.
- El run actual no promueve a Producción. Si la build pasa QA y recibe la aprobación correspondiente, se promueve **este mismo AAB interno**, conservando el mismo `versionCode`, SHA-256, paquete y SHA de fuente; no se recompila para Producción. La carga interna usa la cuenta de servicio guardada en `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`; la comprobación previa verifica paquete, pista y versionCode antes de compilar. Se requiere un job administrativo nuevo ligado al SHA final.
- No se borra el AAB de la 141, no se reescribe su historial, no se reemplaza `main` y no se crea una app Preview adicional.

## Inventario de ramas (evitar fusiones ciegas)
- PR #254 — base de app única Android 141: incluida como historia de la fuente 141.
- PR #258 — reparaciones Android 141: fusionada previamente en la rama unificada.
- PR #261 — corrección de bandera flotante: ancestro del commit 141, no volver a aplicar.
- PR #262 — el commit probado `4f71b250b2fb2fc541bfa0ee1ca0407ffd0c5041` (**324/324 pruebas + compilación Kotlin + arranque de emulador**) **ya es ancestro** del commit 141. El diff adicional hasta `f48408136587a605812cdc6267e36b363ee6273d` no añade una corrección Dart/Kotlin móvil faltante; incorpora cambios del backend push que requieren cambios Supabase. No duplicar ni desplegar esos cambios bajo esta tarea.
- PR #265 — HEAD `d1f382b141f0fb9e4c65ef044047c5c4deea7329` se comparó contra la fuente 141; elimina protecciones/test de invalidación y revierte comportamiento heredado. No integrarlo.
- PR #266 — AAB-only para Play Interna: principalmente canal de distribución, rama divergente. No sustituir el flujo oficial ni importar scripts antiguos ciegamente.
- PR #267/#268 — reglas SQL/avisos de actualizaciones y confirmación de Play 141: **no son funcionalidades Flutter de la app**. No ejecutar migraciones ni alterar producción durante el armado 142.
- Los PR obsoletos o ya incorporados NO se vuelven a fusionar. `main` y producción siguen intactos.

## Única rama de trabajo y entrega
`work/express-single-app-1.6.3-build142` es **el único punto de desarrollo y QA de 142**. Claude debe abrir **esta rama**, verificar `git rev-parse HEAD`, `git status --short` y `grep '^version:' pubspec.yaml`, y traer aquí los cambios adicionales **compatibles y verificados** mediante commits revisables. No reiniciar desde #262/#265, no crear otra app `.qa`, paquete, Firebase, workflow alternativo ni otras ramas candidatas.

Si se descubren cambios de #262/#265 pendientes, registrarlos en el mismo PR con ruta, commit, comportamiento y resultado de prueba antes de incluirlos. Resolver conflictos preservando la versión 141 de producción y las correcciones posteriores verificadas. Evitar merges por la mera fecha del PR.

## Emuladores con Flutter en VS Code (sin generar APK de distribución por cada cambio)
1. Abrir esta rama y confirmar Flutter **3.47.5** (versión fijada en `.github/workflows/build-android.yml`), Android SDK, Java, emulador activo y `flutter doctor -v`.
2. Ejecutar `flutter pub get`, `flutter analyze` y `flutter test`.
3. **Importante**: en este repositorio, el workflow oficial *recrea* `android/` mediante `flutter create --platforms=android --org com.express --project-name usuario1` y luego **aplica el overlay nativo** con `.github/scripts/apply_floating_overlay.py`, regenerando plugins. No confiar en un `android/` antiguo ni en un scaffold sin el overlay de llamadas/ofertas. Adaptar la preparación local con ese mismo procedimiento y validar manifiesto, plugin registrant, Firebase y el package `com.express.usuario1` sin publicar ni filtrar credenciales.
4. `flutter devices` y luego `flutter run -t lib/mobile_main.dart -d <EMULADOR> --debug` en el scaffold oficial preparado. Usar Hot Reload cuando corresponda; reiniciar/compilar debug tras cambios nativos. Esto instala **debug local** para el emulador, no una APK de distribución ni un AAB Play.
5. Probar Taxi pasajero/conductor, Envíos, Delivery cliente, llamadas ZEGO entrantes/segundo plano, ofertas flotantes/expiración/cancelación, mapa, autenticación y contexto Preview/Producción por **cuenta**, notificaciones y perfil. Registrar tests, logs Android, comportamiento y SHA exacto.

## Criterio para producir el APK descargable + AAB interno 142
- Todas las correcciones requeridas incorporadas en ESTA rama; pruebas Flutter completas y compilación Android/Kotlin y QA de emulador **del HEAD final**, no de otro SHA.
- Comprobar exactitud de versión `1.6.3+142`, package `com.express.usuario1`, firma original, Firebase y SHA, comparando con `identity.json` de 141.
- Revisar el workflow de compilación porque conserva el nombre y las rutas `android-141.json`, vinculadas al trabajo anterior. No reutilizar el job ni la autorización de 141, ni modificar silenciosamente la compuerta de seguridad: preparar un **nuevo job autorizado para 142** ligado al SHA final.
- Tras cerrar QA, usar un **job oficial nuevo**, fijado al SHA definitivo de la 142 y con `artifact_type=single-app-candidate-apk+aab`. Compilar **APK + AAB firmados en un único job**, con `identity.json` y SHA-256 real por archivo. El mismo run adjunta la APK/AAB como Release y carga el AAB a Pruebas internas. Si QA aprueba la candidata, promover la misma identidad/hash a Producción mediante el gate administrativo; nunca recompilar una segunda AAB para esa promoción. No reutilizar el job 141 ni cambiar `main` o Supabase.

## Registro obligatorio para Claude — estado real
- **Ya realizado (21-10-2026):** rama `work/express-single-app-1.6.3-build142`, fuente 141 comprobada con manifiesto firmado, versión `1.6.3+142`, comparación de #262/#265 y test de gate alineado a 142 en commit `4ba5220f51856b1d93b40ac4b7e0c2b637f55938`. Suite completa 392/392 PASS; overlay subset 24/24 PASS; test de gate 2/2 PASS. Flutter 3.47.5 generó un scaffold Android local desde cero, el overlay nativo se aplicó y la app debug arrancó en Medium Phone (5554) y Pixel (5556), con `versionCode=142`; en Pixel se observó el panel de conductor y se verificó hot reload/restart.
- **Alcance no certificado:** no se generó una oferta real para validar push vs overlay/cancelación/expiración y llamadas de extremo a extremo; no se crearon datos en backend.
- **Pendiente:** `flutter analyze` global conserva avisos/infos heredados (exit 1); solo el análisis del conjunto crítico indicado por el workflow pasa con flags no-fatales. Falta crear la fila candidata 142 con el RPC administrativo; la sesión Supabase conectada devuelve `auth.uid() = NULL` e `is_admin() = false`, así que la autorización no se omitió. El workflow valida la credencial de Play en su preflight y detiene el job si falta o no puede acceder al paquete/pista. Aún no hay artefactos release 142 ni carga interna. No reutilizar UUID/job 141.
- **Historial granular obligatorio:** mantener `docs/BUILD_142_CHANGELOG.md`, indicando por commit: fecha, SHA, rutas creadas/editadas/eliminadas, qué cambió, por qué, efecto en Taxi/Envíos/Delivery/ZEGO, pruebas exactas y estado. **Si se elimina código/flujo, decir explícitamente qué se quitó y qué lo reemplaza**; si no se eliminó nada, escribir «ninguna eliminación». No marcar como completo algo no ejecutado.
- Los agentes deben leer **`CLAUDE.md` (raíz), `AGENTS.md` y esta guía** al entrar. Todo el trabajo y resultados quedan enlazados desde [PR #270](https://github.com/jorge2610g/Expressdelivery/pull/270), sin crear nuevos PR independientes para la 142.

## Entrega requerida a Claude
Dejar en **el mismo PR**: inventario de PR/commits incluidos, descartados y pendientes; explicación de conflictos; `flutter analyze`, `flutter test`, pruebas Android/QA emulador y SHA final; prueba de package, firma y versionCode, enlaces/hash de ambos artefactos, destino de prueba interna y limitaciones que bloquean compilar/publicar 142.
