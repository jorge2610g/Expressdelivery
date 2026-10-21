# Express Principal 1.6.3+142 — fuente única y trazabilidad

Estado: **candidato de integración, no AAB/APK compilado ni publicación Play**. Orden del propietario: consolidar los cambios ya realizados y probados y devolver a Claude un flujo normal VS Code/Flutter/emuladores; no mantener versiones paralelas.

## Punto de partida verificable
- Aplicación Android **única**: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Fuente elegida: `545b03339b69fc8b89f53f9aec43855772e404a5` (solicitud AAB 141 en `.github/build-requests/android-141.json`; contrastar además `identity.json` de la Release oficial con el artefacto realmente publicado).
- Google Play 141: el PR #268 indica que el canal production publicó `versionCode=141` y un AAB oficial asociado al job `470dc53d-eeef-4acd-bbf9-b226344c043b`. La verificación de Play figura en ese PR; **este documento no es una nueva comprobación de Play Console**.
- Este candidato parte de la fuente 141, **no de main** (que seguía declarando `1.6.2+140`) ni de un checkout local antiguo.
- Versión preparada: `1.6.3+142`. Cambiarla no compila ni publica ningún artefacto.

## Inventario de ramas (evitar fusiones ciegas)
- PR #254 — base de app única Android 141: incluida como historia de la fuente 141.
- PR #258 — reparaciones Android 141: fusionada previamente en la rama unificada.
- PR #261 — corrección de bandera flotante: ancestro del commit 141, no volver a aplicar.
- PR #262 — el commit probado `4f71b250b2fb2fc541bfa0ee1ca0407ffd0c5041` (**324/324 pruebas + compilación Kotlin + arranque de emulador**) **ya es ancestro** del commit 141. NO duplicar estos cambios. El HEAD más reciente `f48408136587a605812cdc6267e36b363ee6273d` contiene cambios posteriores: examinar diff desde 141 y exigir regresión completa antes de integrar. No interpretar el resultado de las pruebas del viejo commit como prueba del nuevo.
- PR #265 — barra flotante de 30 segundos y cierre por Realtime: **solo verificaciones estáticas declaradas; sin compilación Android ni QA real confirmadas**. No marcar listo; integrar solo tras pruebas y verificar interacción con #262 y backend.
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

## Criterio para producir el único AAB 142
- Todas las correcciones requeridas incorporadas en ESTA rama; pruebas Flutter completas y compilación Android/Kotlin y QA de emulador **del HEAD final**, no de otro SHA.
- Comprobar exactitud de versión `1.6.3+142`, package `com.express.usuario1`, firma original, Firebase y SHA, comparando con `identity.json` de 141.
- Revisar el workflow de compilación porque conserva el nombre y las rutas `android-141.json`, vinculadas al trabajo anterior. No reutilizar el job ni la autorización de 141, ni modificar silenciosamente la compuerta de seguridad: preparar un **nuevo job autorizado para 142** ligado al SHA final.
- Solo entonces compilar un AAB firmado por el **pipeline oficial**, registrar URL y SHA-256 reales y devolver evidencia. **Publicar o promover en Google Play requiere aprobación independiente**. Nunca modificar `main`, desplegar Supabase ni Producción por esta orden de integración.

## Entrega requerida a Claude
Dejar en **el mismo PR**: inventario de PR/commits incluidos, descartados y pendientes; explicación de conflictos; `flutter analyze`, `flutter test`, pruebas Android/QA emulador y SHA final; prueba de package, firma y versionCode; y limitaciones que bloquean compilar/publicar 142.
