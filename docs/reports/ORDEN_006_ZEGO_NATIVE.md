# ORDEN 006 — Llamadas nativas Android sin SYSTEM_ALERT_WINDOW

- **Coordinador:** ChatGPT · **Ejecutor:** Claude Code (con subagentes de solo lectura)
- **Rama de este informe:** `docs/zego-native-calls-design-20261015` (desde `origin/main` 95e22e27)
- **Estado:** diseño técnico entregado; **sin prototipo y sin PR**, porque no se cumplen las tres condiciones de la orden (ciclo de vida, tonos únicos, Taxi y Envíos intactos) sin dispositivos.
- **Restricciones respetadas:** no se tocaron PR #248, PR #249, `main`, Producción, Supabase ni Google Play; no se generó APK.
- **Relación con PR #249:** #249 mantiene la vía soportada por ZEGO (SAW). Este informe analiza la alternativa sin SAW.

## 0. Conclusiones

1. **La notificación nativa con Aceptar/Rechazar ya existe** en el plugin `flutter_callkit_incoming` 3.0.0: CallStyle en Android 14+ y diseño personalizado en versiones anteriores. El bloqueo es la compuerta de ZEGO, no la falta de capacidad nativa.
2. **Sin SAW, ZEGO no entrega la llamada a esa notificación cuando la app está viva en segundo plano.** Su rama de fondo suena (tono de ZEGO) y dibuja una pantalla invisible.
3. **Una notificación propia no puede aceptar ni rechazar la invitación de ZEGO** por sí sola: la aceptación de ZEGO depende de `invitationID` e `inviter` de su estado interno, y el UUID del plugin no está ligado al `callID` (ver §2.2).
4. **Riesgo de tono doble verificado en código**, y **no existe una opción pública de ZEGO para silenciar su tono** (ver §2.4).
5. **`endAllCalls` es global**: cualquier fin de llamada de ZEGO termina también las notificaciones creadas por la app (ver §2.3).
6. **Decisión recomendada:** no implementar ahora. Elegir entre (a) mantener #249 con aceptación del permiso y revisión de Play; (b) una ruta offline de ZEGO que desconecte la señalización en segundo plano, como piloto con dispositivos; o (c) un rediseño de señalización propia con FCM. Las opciones se comparan en §4.

## 1. Lo que Android permite (fuentes oficiales leídas)

| Requisito | Fuente | Estado |
|---|---|---|
| Incoming-call CallStyle requiere acciones Responder y Rechazar | developer.android.com/develop/ui/views/notifications/call-style | VERIFICADO (cita) |
| `forIncomingCall` con `Person` con nombre; `addPerson` en el ejemplo | misma guía | VERIFICADO (ejemplo); condiciones adicionales NO VERIFICADO |
| CallStyle con API 31: dato de búsqueda; referencia de clase no legible | Notification.CallStyle | NO VERIFICADO del texto oficial |
| Pantalla completa sin USE_FULL_SCREEN_INTENT en el manifest no se lanza (target 10+) | developer.android.com/develop/ui/views/notifications/time-sensitive | VERIFICADO (cita) |
| Con dispositivo en uso, la pantalla completa se muestra como heads-up | misma página | VERIFICADO (cita); caso "permiso denegado" NO VERIFICADO |
| Comportamiento cuando el permiso de pantalla completa está denegado | source.android.com/docs/core/permissions/fsi-limits | INACCESIBLE desde el entorno; solo paráfrasis de búsqueda |
| Pantalla completa, targetSdk 34+: concesión por defecto solo para apps de llamadas y alarmas; Play revoca la concesión a apps que no encajan | developer.android.com/about/versions/14/behavior-changes-14 | VERIFICADO (cita) |
| `canUseFullScreenIntent()` y `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` | misma página | VERIFICADO |
| Iniciar actividades desde segundo plano: excepción por SAW concedido | developer.android.com/guide/components/activities/background-starts | VERIFICADO; la pantalla completa no aparece nombrada |
| POST_NOTIFICATIONS en Android 13+ | developer.android.com/training/notify-user/notification-permission | VERIFICADO (cita) |
| Llamadas autogestionadas con CallStyle no necesitan POST_NOTIFICATIONS | misma página | VERIFICADO (cita); aplica solo a MANAGE_OWN_CALLS |
| FGS `phoneCall`: manifest `FOREGROUND_SERVICE_PHONE_CALL` y MANAGE_OWN_CALLS o rol de marcador | developer.android.com/develop/background-work/services/fgs/service-types | VERIFICADO (cita) |
| Android 15+ (targetSdk 36): no iniciar FGS `phoneCall` desde BOOT_COMPLETED | misma página | VERIFICADO (cita) |
| SYSTEM_ALERT_WINDOW debe declararse en el manifest para concederse | Settings / Manifest.permission | INACCESIBLE; solo fuentes secundarias |

## 2. Integración ZEGO + CallKit (evidencia de código)

Rutas: `P` = `zego_uikit_prebuilt_call-4.24.4/lib/src/invitation`; `F` = `flutter_callkit_incoming-3.0.0/android/src/main/kotlin/com/hiennv/flutter_callkit_incoming`. Hallazgos de un subagente de solo lectura. Las referencias de línea son suyas; el ejecutor no las recomprobó todas, así que deben revisarse antes de usarlas en código.

### 2.1 Quién escucha los eventos nativos (Q1)

- **Isolate principal:** `P/mixins/private/callkit.dart:81` registra `_onAndroidCallKitIncomingEvent`.
  - **Accept** (`:152-165`): marca `hasInvitation=false`, trae la app al frente y llama `acceptInvitationInBackground()` (`P/callkit/background_service.dart:40`).
  - **Decline / Timeout** (`:166-178`): llaman `refuseInvitationInBackground()` (`background_service.dart:90`).
  - **Ended** (`:179-180`): sin acción. No llama `stopRing`.
- **Isolate de fondo:** `P/callkit/android/handler.call.dart:351` (llamado desde `:283`).
  - Un guard en `:360-379` descarta eventos si el isolate principal ya registró su puerto.
  - **Accept** (`:398-424`): escribe `accept=true` en caché y llama `_acceptCallInvitation` (`:158`).
  - **Decline / Timeout** (`:425-428`): llaman `_refuseCallInvitation` (`:123`).

### 2.2 ¿Puede una notificación propia aceptar la invitación de ZEGO? (Q2) — **No, sin trabajo adicional**

- `acceptInvitationInBackground` retorna sin efecto si `_pageManager.hasCallkitIncomingCauseAppInBackground` es falso (`background_service.dart:41-52`). Esa bandera solo se activa cuando ZEGO muestra su propia notificación (`page_manager.dart:1230`).
- Además no hace nada si `invitationData.callID` está vacío (`:54`), y usa `invitationData.invitationID` e `inviter.id` del estado de ZEGO (`:57-61`).
- La API pública `accept({customData})` (`P/service.dart:785-789`) **no recibe `invitationID`**; actúa sobre la invitación actual.
- En el isolate de fondo el `invitationID` sale del mensaje de push de señalización (`handler.call.dart:185-195`).
- El `id` de la notificación del plugin es `const Uuid().v4()` (`P/internal/callkit_incoming.dart:75`). El `callID` de ZEGO solo viaja en el texto `handle` si `callIDVisibility` está activo (`:64-66`); `extra` queda vacío (`:88`). **Ningún código liga el UUID del plugin con el `callID`.**
- **No verificado:** si la bandera de aceptación pendiente se consume más tarde.

### 2.3 Cancelación, timeout y fin de llamada (Q3)

- La notificación de ZEGO se cierra con `dismissNotification(_callInvitationNotificationID)` (`P/notification/notification_manager.dart:222-233`), desde `restoreToIdle` (`page_manager.dart:2024`).
- Las notificaciones nativas se cierran con `FlutterCallkitIncoming.endAllCalls()` (`P/internal/callkit_incoming.dart:181-188`), llamado desde `restoreToIdle` (`page_manager.dart:2043`), `:832`, `:2285`, `:2301`, y en el isolate de fondo al cancelar o expirar (`handler.call.dart:118, 202, 521`).
- `endAllCalls` (`F/FlutterCallkitIncomingPlugin.kt:177-188`) envía un broadcast ENDED por cada entrada de la lista `ACTIVE_CALLS` y luego la vacía. Las entradas se añaden en `ACTION_CALL_INCOMING` (`CallkitIncomingBroadcastReceiver.kt:95-100`).
- **Conclusión:** `endAllCalls` **no filtra por id**. Cualquier cierre de ZEGO termina también las notificaciones creadas por la app.
- **Riesgo de cancelación perdida:** si el teléfono no tiene la sesión de señalización activa, la cancelación del emisor no llega, y la notificación nativa queda sonando hasta el timeout. Un push de `cancel_invitation` existe en el modelo de mensajes (`P/callkit/...` y documentación interna), pero su entrega depende de FCM (**no verificado en dispositivo**).

### 2.4 Tono y tono duplicado (Q4 y Q5)

- El tono de llamada de ZEGO (`_calleeRingtone.startRing`) se inicia **solo** en `showNotificationOnInvitationReceived` (`page_manager.dart:1455`). Ese método se llama en primer plano (`:1254`) y en segundo plano solo cuando la compuerta de superposición falla (`notification_manager.dart:404-416`, luego `page_manager.dart:1236-1243`).
- Con superposición concedida, `showInvitationNotification` llama `showCallkitIncoming` (`notification_manager.dart:430`) y **no** llama `startRing`. Los únicos llamadores de `startRing` son `page_manager.dart:542` y `:1455`.
- El tono nativo lo reproduce `CallkitSoundPlayerManager.play`, invocado desde `showIncomingNotification` (`F/CallkitNotificationManager.kt:994-997`) solo si `incomingChannelEnabled()` es verdadero (`:871-874`). Usa `USAGE_NOTIFICATION_RINGTONE`; si el nombre del tono está vacío o no resuelve, usa el tono del sistema (`CallkitSoundPlayerManager.kt:134-156`). `prepare()` detiene el tono previo (`:70-72`) y el gestor es singleton de proceso.
- **Tono de ZEGO:** se detiene en `page_manager.dart:617` (tras aceptar) y `restoreToIdle` (`:2009-2010`). El manejador nativo de aceptar/rechazar no llama `stopRing` directamente.
- **Opciones para silenciar el tono de ZEGO** (`P/config.dart:695-700`, `P/config.defines.dart`, `P/events.dart:13-48`):
  - `ZegoCallRingtoneConfig.incomingCallPath` solo define el archivo de sonido, sin opción de desactivar. La documentación indica que «solo funciona para llamadas en línea».
  - `ZegoCallInvitationNotifyPopUpUIConfig.visible = false` oculta la hoja superior (`page_manager.dart:2162-2170`), pero **no** evita `startRing` (que ocurre antes, en `:1455`).
  - `callChannel.sound` cambia el sonido nativo, no lo desactiva.
  - Los eventos de invitación son callbacks, no interruptores.
  - **Resultado: no se encontró forma pública de desactivar el tono de ZEGO.**
- **Conclusión:** en el camino sin superposición, el usuario oye dos tonos (nativo y el de `startRing`). Con superposición y notificación propia junto con la de ZEGO, ambas notificaciones comparten un solo reproductor, por lo que probablemente se oye un tono. **El resultado audible no está verificado en ejecución.**

### 2.5 Evento nativo con el motor Flutter apagado (Q6)

- El botón Aceptar es un `PendingIntent` a `TransparentActivity` con `ACTION_CALL_ACCEPT` (`F/CallkitNotificationManager.kt:938-941`). Esa actividad envía un broadcast ACCEPT con `FLAG_RECEIVER_FOREGROUND`, arranca el lanzador con la acción y los datos (`AppUtils.kt:8-14`) y termina.
- El receptor (`CallkitIncomingBroadcastReceiver.kt:120-130`) ejecuta los listeners nativos y luego `sendEventFlutter` (`:261`), que llama a `FlutterCallkitIncomingPlugin.sendEvent` (`:46-49`). Ese método publica en el hilo principal y llama `eventSink?.success`. **Si no hay sink adjunto, el evento se descarta: no hay cola.**
- El isolate de fondo solo recibe el evento si su propio motor se adjuntó y registró un `EventChannel` (`F/FlutterCallkitIncomingPlugin.kt:137-142, 100-116`).
- **No verificado:** qué código crea ese motor de fondo, y el orden entre el arranque de la app y el registro del isolate.

## 3. Requisitos por opción y riesgos

Riesgos de un diseño solo nativo, por orden de gravedad:

1. **Aceptar/rechazar no se conecta con ZEGO** sin `invitationID`, `inviter` ni el estado de la página. Sin ese vínculo, las acciones fallan en silencio o quedan aplazadas (`background_service.dart:41-61`).
2. **Tono doble o persistente:** `startRing` de ZEGO más el tono nativo; no hay forma pública de silenciar el primero.
3. **Cierre global:** `endAllCalls` termina todas las notificaciones de la app ante cualquier evento de ZEGO.
4. **Cancelación perdida** si la señalización no está activa en segundo plano: notificación sonando hasta el timeout.
5. **Dependencia de push:** la ruta offline necesita `ZEGO_RESOURCE_ID` y PushID configurados (`P/service.dart:708`: «resourceID… ringtone for offline call invitations»).

## 4. Opciones comparadas (con #249 como referencia)

| Criterio | A. #249 (SAW + ruta ZEGO) | B. Piloto offline ZEGO (desconectar en segundo plano) | C. Señalización propia por FCM |
|---|---|---|---|
| Permiso sensible | SAW (manual) | Sin SAW | Sin SAW |
| Ruta de aceptación | Soportada por ZEGO | Soportada para push offline (`handler.call.dart:330`, sin compuerta) | Propia; requiere backend nuevo |
| Tono doble | Evitado (una notificación nativa) | Sin tono de `startRing` en isolate de fondo (**a verificar**) | Propio; control total |
| Cancelación perdida | Evitada (señalización viva) | Riesgo real; depende de push de cancelación | Depende de FCM |
| Cambios en Taxi/Envíos | Solo permiso y textos | Cambia el ciclo de vida de la voz en segundo plano | Cambia el flujo de invitación |
| Verificable aquí | Sí (tests y CI, #249) | No | No |
| Esfuerzo | Ya hecho | Alto y riesgoso | Muy alto |

**Recomendación:** no prototipar B ni C en esta orden. Si el propietario no acepta SAW, el paso siguiente es un piloto B detrás de bandera, en rama aparte, solo después de: (1) confirmar la configuración de push en la consola de ZEGO, (2) una matriz de pruebas con dos teléfonos, (3) pruebas de cancelación y timeout, y (4) autorización expresa porque cambia la voz en segundo plano de Taxi y Envíos.

## 5. Notificación utilizable sin pantalla completa (punto 3)

- El plugin siempre publica la notificación y marca pantalla completa (`F/CallkitNotificationManager.kt:192-194`), sin comprobar `canUseFullScreenIntent()`. Sin el permiso, Android debería mostrarla como heads-up (VERIFICADO solo para el caso con dispositivo en uso; el caso denegado **NO VERIFICADO**).
- El canal `callkit_incoming_channel_id` se crea con importancia alta y visibilidad pública en pantalla de bloqueo (`CallkitNotificationManager.kt:872-911`). **El código no puede subir la importancia de un canal que el usuario haya bajado**.
- Requisitos mínimos verificados: POST_NOTIFICATIONS concedido (Android 13+), canal no silenciado por el usuario.
- Diseño propuesto: no depender de pantalla completa para responder; mantener los botones CallStyle; comprobar `FlutterCallkitIncoming.canUseFullScreenIntent()` (API existe en `flutter_callkit_incoming.dart:144`) y ofrecer un aviso para conceder el permiso. **Aviso y textos: decisión de producto.**

## 6. Google Play (sin afirmar aprobación)

- Ningún punto de esta sección implica que la app esté aprobada por Google Play.
- **Pantalla completa:** para targetSdk 34+, la concesión por defecto se limita a apps de llamadas y alarmas (VERIFICADO). La declaración en Play Console para este permiso **no está verificada**.
- **FGS `phoneCall`:** requiere declaración de tipo de servicio en Play Console desde Android 14 (paráfrasis de búsqueda, **no verificada**).
- **SYSTEM_ALERT_WINDOW:** criterio de Play **no verificado**. Es el punto central de la decisión de #249.
- **READ_PHONE_STATE:** presente en el APK QA; su origen no está verificado (ver ORDEN 005). Puede implicar requisitos de política de privacidad (fuentes de foros, **no verificado**).
- **PERMISSION_CALL con `protectionLevel="normal"`** (`F/AndroidManifest.xml:19`): exposición real de componentes exportados; la corrección propuesta a `signature` está en ORDEN 005 y no se aplicó.
- **Para confirmar en Play Console:** declaración de pantalla completa, declaración de FGS `phoneCall`, SAW, READ_PHONE_STATE, y si la categoría de la app califica para concesión por defecto.

## 7. Pruebas y comparación con #249

- **Prueba de sensibilidad:** se ejecutó el contrato de #249 (`test/android_voice_permission_contract_test.dart` en `3b4c8ca8`) sobre `origin/main` 95e22e27 en un worktree temporal. **Resultado: 2 pruebas fallan**, con `SYSTEM_ALERT_WINDOW` a 0 (esperado ≥2) y `ZegoCallInvitationPermission.systemAlertWindow` a 0 (esperado 2). El contrato detecta la ausencia del cambio. El worktree se eliminó.
- **Resultados de #249:** 12/12 pruebas de voz y ZEGO pasan (orden anterior). CI del head `3b4c8ca8`: `validate`, `guard`, `change-inventory`, `Shared Flutter checks and production-format Web` y `Vercel Preview Comments`, todos `success` (comprobado tras el seguimiento programado).
- **Pruebas del diseño B/C:** no se añadieron, porque no hay código. La matriz de pruebas físicas está en `docs/ZEGO_OVERLAY_INCOMING_CALL_DIAGNOSIS_20261015.md` §7 (en #249).
- **Vista previa de Vercel:** la integración de Vercel crea una vista previa automática por PR (`Deployment has completed`). No se solicitó. `AGENTS.md` prohíbe webs de prueba adicionales; decisión pendiente (ORDEN 005, §8).

## 8. Límites de esta verificación

- Sin dispositivos Android ni Android SDK: ningún comportamiento de runtime está verificado.
- Inaccesibles desde el entorno: `docs.zegocloud.com`, `support.google.com`, `source.android.com`, `storage.zego.im`, `maven.google.com`.
- No verificado: audibilidad real de tonos; entrega de push de cancelación; comportamiento de pantalla completa denegada; origen del motor de fondo; si la bandera de aceptación pendiente se consume.

## 9. Decisiones para el propietario

1. Mantener #249 (SAW) con aceptación del permiso y revisión de Play, o rechazar SAW.
2. Si se rechaza SAW: autorizar un piloto B en rama aparte con matriz de dos teléfonos, o descartar la alternativa.
3. Confirmar en Play Console las declaraciones de pantalla completa, FGS `phoneCall`, SAW y READ_PHONE_STATE.
4. Decidir la integración de Vercel por PR.

## 10. Fuentes

- Locales (caché de pub): `zego_uikit_prebuilt_call` 4.24.4, `zego_uikit_signaling_plugin` 2.8.21, `flutter_callkit_incoming` 3.0.0, `zego_plugin_adapter` 2.14.2.
- developer.android.com: cambios de Android 14, inicio de actividades en segundo plano, guía de CallStyle, notificaciones con prioridad temporal, permiso POST_NOTIFICATIONS, tipos de servicio en primer plano.
- Informe de subagente de solo lectura sobre la integración ZEGO + CallKit (ver §2) y de subagente sobre requisitos Android y Play (ver §1 y §6).
