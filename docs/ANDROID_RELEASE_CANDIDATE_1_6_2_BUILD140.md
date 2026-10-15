# Express Android — paquete oficial pendiente de aprobación

## Identidad del candidato preparado

- App: `com.express.usuario1`, entrada Flutter `lib/mobile_main.dart`.
- Versión fuente: `1.6.2+140`, respaldada por el siguiente `versionCode` del registro `app_release_gate` en Supabase (`production_store_build_number=139`, `next_production_build_number=140`) al 14/10/2026.
- Una sola APK oficial y su AAB firmado; la compilación es un **candidato QA**, no una publicación Play ni certificación física.
- Antes de autorizar el build, fijar y comparar SHA completo de `main`/rama de release, build_jobs.commit_sha y hash del árbol.
- Artefactos: APK, AAB y manifiesto de identidad; al compilar deben persistirse las huellas SHA-256 y el run de GitHub. La firma debe ser la oficial.
- GitHub Action `build-android.yml`: no dispone de cron ni trigger push. Solo `workflow_dispatch` con UUID del trabajo autorizado y campo `AUTORIZO APK QA`.
- El pipeline aborta si cambia el SHA del commit, el nombre de versión o el build number solicitado; no sustituir por otro SHA silenciosamente.
- **Play Store:** no existe acción de promoción automática en este procedimiento. Necesita aprobación independiente después del QA Android.

## Puertas de calidad y configuración antes de autorizar el build

| Puerta | Comprobación | Estado inicial |
| --- | --- | --- |
| CI Flutter | Análisis completo + pruebas + builds web | Aprobar sobre SHA de release después del merge |
| Llamadas ZEGO | Configurar `ZEGO_RESOURCE_ID` real, FCM Data Messages y notificaciones Android | Pendiente: no hay Resource ID en los registros anteriores |
| Revisión documentos | Aplicar y verificar migración `20261015000500_generic_driver_document_photo_review_v2.sql` con cuentas QA, panel y notificaciones; mantener desactivada hasta entonces | Código fusionado; migración sin aplicar |
| Tarifas/premios | No aplicar PR #222/#190 antes de aprobar reglas económicas | Desactivados |
| Oferta Taxi/Envíos | Medir recepción, zonas, servicio, latencia, estado offline/reanudación | Prueba física pendiente |
| Foto/GPS/push | Verificar cámara, permisos, GPS activo/segundo plano, Push Android | Prueba física pendiente |
| Artefacto | Validar paquete, firma, versionCode 140, hashes y origen | Pendiente de compilación explícita |

## Procedimiento para la siguiente autorización

1. Finalizar las puertas de configuración y QA que puedan ejecutarse sin APK.
2. Confirmar `main` y el commit SHA exacto; asegurar que Supabase `build_jobs` no tenga trabajos previos pendientes.
3. Crear **un único** `build_jobs` para versión 1.6.2+140 con `commit_sha` de ese candidato, `single-app-candidate-apk+aab`; esto requiere aprobación del dueño.
4. Despachar manualmente GitHub Action con ese `job_id` y la frase `AUTORIZO APK QA`; no publicar aún.
5. Descargar el candidato firmado, verificar Android físico en dos teléfonos y registrar evidencia.
6. **Solo con nuevo visto bueno**, promocionar exactamente el AAB y sus hashes probados a Google Play.

## Excepciones expresas

Un fallo de configuración de ZEGO, de QA de documentos o una tarifa sin política definida **no se considera PASS**. Se informa como bloqueo; no inventar credenciales ni dar por hecho que una prueba Flutter valida el audio físico.
