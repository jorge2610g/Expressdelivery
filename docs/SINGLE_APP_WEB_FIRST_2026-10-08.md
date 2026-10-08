## Gate Android de aplicación única · 2026-10-08

El nuevo circuito ya no exige APK Preview: AdminExpress crea un candidato
`single-app-candidate-apk+aab` desde `main`; GitHub Actions compila el
**APK y AAB firmados de com.express.usuario1**. El Release del candidato
se identifica por SHA y job ID; sus hashes se guardan en Supabase.
El administrador prueba ese APK, registra las pruebas reales, aprueba
los hashes y promueve exactamente el mismo APK/AAB **sin recompilar**.
Publicar a clientes sigue siendo una acción distinta y manual.

El gate antiguo no se usa para esta nueva ruta, pero se conserva manual
para recuperación hasta que el primer candidato unificado pase QA físico.
El aislamiento de datos Preview/Producción no cambia. La app QA temporal
sirve para tests nativos, NO certifica el APK oficial firmado.

# Express — Aplicación única, Web primero (2026-10-08)

## Decisión del propietario

Express mantiene **un solo producto Flutter** para pasajero, conductor y Delivery.
Los cambios de UI y lógica compartida se revisan primero en la **Web real**;
no se debe generar un APK Preview permanente por cada commit.

- Web: `lib/web_preview.dart` (bootstrap de navegador).
- Android: `lib/mobile_main.dart` (único bootstrap nativo).
- Ambos importan los mismos módulos de negocio y pantallas. La Web no puede
  ejecutar las API nativas de Android; no afirmar paridad total sin pruebas.
- Aplicación Android pública: `com.express.usuario1`, APK + AAB firmados para
  Google Play, con su contador de versión y firma vigentes.
- `preview` y `production` **siguen siendo canales de datos independientes**
  en Supabase. Eliminar un APK duplicado **no** elimina esa separación.

## Nuevo ciclo cotidiano

1. Cambiar la única implementación Flutter compartida.
2. Abrir PR contra `main`. `Express Single App - Web First QA` ejecuta
   análisis de **ambos entrypoints**, pruebas Flutter y compilación Web,
   usando el SHA de la rama, sin publicar ningún APK.
3. Incorporar cambios probados. `deploy-web.yml` sigue comprobando
   regresiones y publicando el sitio real desde `main`.
4. **Solo** cuando una función requiera Android nativo, abrir Actions →
   `Express Single App - Web First QA` → Run workflow →
   `native_android=true`. Compila `lib/mobile_main.dart`, no una copia,
   en el contenedor temporal `com.express.usuario.qa` y runtime de datos QA.
   El APK temporal dura un día como artefacto de Actions; no crea una release,
   no modifica Google Play, no usa ni cambia la firma de Producción.
   Este APK sirve para verificar compilación/contendor nativo; su configuración
   Firebase/OAuth puede no estar provisionada, por lo que **no** certifica
   por sí solo login, FCM, Didit, GPS físico ni una publicación Android.
5. Para una release real, efectuar QA Android físico/emulador y controlar
   versión, SHA, permisos, firma y build AAB según el gate vigente.

## Qué se desactiva en esta fase

- `shorebird-preview-codepush.yml`: sin trigger automático por cambios
  de `main`; únicamente operación manual **legacy** para recuperación o
  certificación de un release mientras se migra el gate.
- `express-qa.yml`: sin ejecución por cada Shorebird ni cron; sigue
  disponible manualmente cuando hace falta certificar Android real.
- `shorebird-bootstrap-preview.yml`: únicamente manual legacy.
- `demand-preview-patch.yml`: eliminado del flujo principal; el workflow
  estaba fijado a la versión histórica 1.5.79+120.
- `experiment/live-preview-mirror`, `refactor/unified-android-release-20261006`
  y `workflow/web-preview-primary-20261007` son referencias históricas:
  al 2026-10-08 estaban detrás de `main`, sin cambios nuevos que integrar.
  **Sus tres referencias ya se eliminaron** con una acción de GitHub que volvió
  a verificar que eran ancestros de `main`; no se borró ningún commit único.
  La rama de respaldo `backup/pre-single-app-web-first-20261008` continúa.

## Dependencia transitoria: release gate de Producción

**No declarar cerrada la desduplicación Android todavía.**

La Edge Function `android-build-worker`, los jobs
`candidate-apk+aab` / `apk+aab`, `app_release_gate` y el panel de
aprobación continúan exigiendo un **Preview Shorebird certificado** para
promover un AAB de Producción. La integración nueva **no cambia** ese
contrato ni la firma: eliminarlo sin reemplazo verificable podría bloquear
Google Play o permitir publicar código sin QA.

Por lo tanto el workflow legacy queda manual, no automático, **hasta**
migrar el gate a certificación del **SHA + candidato Android real**
mediante QA explícito y preservar la promoción del mismo artefacto sin
recompilar. No invocar los workflows legacy en tareas Dart/Web corrientes.

## Criterios pendientes para cierre completo

1. Migrar el gate, la función `android-build-worker` y controles Admin para
   aprobar únicamente el APK/AAB de Producción por SHA, sin exigir una
   segunda app Preview.
2. Validar `release → QA Android real → aprobación → promoción del mismo
   candidato`, firmas, Firebase, permisos, notificaciones y rollback.
3. Eliminar workflows legacy y paquete Preview de los circuitos de release
   únicamente tras pruebas y respaldo de la configuración anterior.
4. **Completado:** eliminadas las tres ramas experimentales fusionadas; las
   ramas con trabajo exclusivo, tags, builds, datos reales y respaldos siguen
   intactos.
5. Conservar QA automatizado backend/Web y las barreras `preview/production`.
   No usar QA sintético para modificar pedidos reales.

## Recuperación

- Baseline exacta de `main` antes de este cambio:
  `db8b15b31eb59993508fe9b8d58430db8aa0738b`
- Rama respaldo: `backup/pre-single-app-web-first-20261008`.
- Rama de implementación: `refactor/single-app-web-first-20261008`.
- No se han modificado tablas de Supabase, claves, firmas, apps instaladas,
  la publicación Google Play ni el contador Google Play como parte de esta fase.
