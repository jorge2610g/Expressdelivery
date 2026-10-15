# Restaurar llamadas de voz entrantes en segundo plano — Express Android

> **Actualización 15-10-2026:** la causa de «suena sin pantalla» en segundo plano y el PR en borrador que añade el permiso de superposición están en `docs/ZEGO_OVERLAY_INCOMING_CALL_DIAGNOSIS_20261015.md`. El punto 6 de este runbook sigue vigente hasta que el propietario decida.

**Incidente:** 14-10-2026; entorno Producción; APK `1.6.1+140`; app Android `com.express.usuario1`.

## Qué se confirmó
- 21:16–21:17 UTC: tres invitaciones en Producción, todas quedaron en estado `initiated` sin `answered_at`. La señalización ZEGO logró enviar tres invitaciones y registró `zego_incoming_call_received` en algunas cuentas/dispositivos. **Eso demuestra que el SDK recibió un evento, NO que Android mostró una pantalla o que alguien contestó.**
- En todas las invitaciones de esa ventana: `resource_id_configured = false`. El backend `zego-call` retorna `resourceID: null` cuando no existe `ZEGO_RESOURCE_ID`.
- Permisos Android `ANDROID_NOTIFICATION_PERMISSION_RESULT`: `granted=true`; `FCM_TOKEN_REGISTERED` existe. El token FCM **general de Express** no equivale a la vinculación de Push ID para notificaciones ZEGOCLOUD.
- Anteriormente ZIM falló con `50131` y `6000121`; la corrección del Token04 servidor quedó en Edge `zego-call` v10. El historial no demuestra que todos los usuarios logren conectarse de forma estable.
- El repo recrea el directorio `android/` durante cada build en `.github/workflows/build-android.yml`; no está versionado el `AndroidManifest.xml` final. Cualquier ajuste Android debe hacerse en el **scaffold del workflow**, sin crear un archivo android/ que luego se borre.

## Configuración necesaria por proyecto (sin compartir secretos por chat ni Git)
1. En **Firebase Console** ubicar el proyecto FCM Android usado para la aplicación de Producción, paquete **`com.express.usuario1`**. Confirmar que corresponde al ID de remitente de los builds. El paquete de Preview **`com.express.usuario.preview`** es distinto.
2. En **ZEGOCLOUD Console**, mismo proyecto que `ZEGO_APP_ID` + `ZEGO_SERVER_SECRET` del Edge Function, ir a configuración de Push/FCM/ZPNs. Configurar credencial **FCM HTTP v1 / Service Account** de ese mismo proyecto Firebase, con acceso adecuado, desde el panel seguro del proveedor. No guardar JSON privado en repo.
3. Crear un **Push Resource ID para Call Kit**, seleccionando **FCM: Data messages** (no Notification messages). Copiar solo el identificador del recurso, exactamente como se generó. Verificar que la función offline/push esté habilitada y que **ZIM** tenga el servicio necesario.
4. En **Supabase Dashboard → Edge Functions → Secrets** del proyecto `zgpijrznvaskgcmauwxx`, configurar `ZEGO_RESOURCE_ID` con ese identificador exacto. Esta variable ya se lee en `supabase/functions/zego-call/index.ts` y se pasa a `ZegoUIKitPrebuiltCallInvitationService.send(resourceID: ...)`. No hay que hardcodearla ni exponer el Server Secret.
5. Validar **PushID ZPNs** real registrado por el dispositivo receptor de llamadas (ZEGO Console Push Debug / logs del SDK) en Producción, sin confundirlo con `native_push_tokens.token`. Configurar Push Debug contra un usuario de prueba.
6. Verificar el **manifest Android resultante**, no solo fuente: permisos y servicios necesarios de ZEGOCLOUD (incluyendo notificación, micrófono, wake locks, ventana emergente, si el modelo Android lo permite) y posibles conflictos entre el receptor FCM estándar de Flutter y el de ZEGO. Comparar con la integración oficial antes de añadir permisos sensibles de Android. **No añadir `SYSTEM_ALERT_WINDOW` automáticamente**: requiere política/permisos del sistema y QA del paquete Play.
7. En el teléfono: permitir notificaciones, notificaciones en pantalla de bloqueo, visualización emergente si el fabricante ofrece el control, datos en segundo plano y batería sin restricciones. Verificar modo No molestar.

## Escenarios de QA (cada uno con Taxi y Envíos)
- **A:** dos dispositivos con la app visible: enviar, sonar, aceptar, audio bidireccional y colgar.
- **B:** receptor **minimizado** (pantalla de inicio, app viva): llegar como llamada y abrir controles.
- **C:** receptor con **pantalla bloqueada**: notificación de llamada, responder y audio.
- **D:** app terminada por el sistema o forzada a cerrar: comportamiento de notificación según fabricante, ZEGO/FCM y limitaciones Android. No prometer que Android entregará todas las notificaciones después de un *force stop* manual.
- **E:** receptor sin señal y posterior reconexión: sin registros fantasma que figuren como `answered`.
- **F:** pasajero→conductor y conductor→pasajero; no enviar entre Preview/Producción.
- Verificar `private_voice_calls.status`, `answered_at`, y en `app_error_logs` eventos `zego_incoming_call_received` / `zego_invitation_error`. Un estado `initiated` o `send_success` **no es prueba de llamada entregada/contestada**.

## Importante para publicar
La PR #240 prepara una recuperación de ZIM al volver a primer plano. **No suple el push offline ni habilita por sí sola llamadas en background**. No fusionar ni publicar una APK hasta una prueba real en Preview y una revisión del manifest final/SDK Android. Mantener el taxi de Producción sin cambios de APK.

Documentación del proveedor:
- https://www.zegocloud.com/docs/uikit/callkit-flutter/quick-start-(with-call-invitation)
- https://www.zegocloud.com/docs/uikit/callkit-flutter/troubleshooting-call-invitations
- https://www.zegocloud.com/docs/uikit/callkit-flutter/invitation-config/api-for-call-invitation
