# ORDEN 005 — ZEGO / Android: alternativas a SYSTEM_ALERT_WINDOW, permisos y estado de CI

- **PR:** #249 (borrador, no fusionado): https://github.com/jorge2610g/Expressdelivery/pull/249
- **Rama:** `fix/zego-android-overlay-call-ui-20261015` · **Commit de código auditado:** `0f9e6e5`
- **Fecha:** 15-10-2026
- **Alcance:** informe. Sin cambios de código, sin fusión, sin despliegue, sin APK, sin cambios en Producción ni en Supabase.

## 0. Respuestas breves

| # | Pregunta | Respuesta |
|---|---|---|
| 1 | ¿Aceptar/Rechazar en segundo plano sin SAW? | Sí a nivel Android: CallStyle y la pantalla completa no exigen SAW. En esta app, no sin rediseñar la ruta de segundo plano de ZEGO, que exige SAW. No es segura ni verificable en esta orden, así que es una decisión de producto. |
| 2 | ¿Qué solución conviene? | Mantener la ruta actual (SAW, PR #249) como opción mínima y soportada, condicionada a la decisión del propietario y a la revisión de Play. Las alternativas sin SAW requieren rediseño. |
| 3 | ¿PERMISSION_CALL y READ_PHONE_STATE? | PERMISSION_CALL: propuesta de `signature`, no aplicada (requiere build de Android y prueba física). READ_PHONE_STATE: origen no verificable aquí; no retirarlo. |
| 4 | ¿Estado final de CI? | Los 5 checks del head `0f9e6e5` terminaron en verde (§4). |
| 5 | ¿Mejora segura y verificable? | Ninguna cumple ambos requisitos sin decisión de producto o sin build. No hubo cambios de código. |

## 1. Pregunta 1: Aceptar/Rechazar en segundo plano sin SAW

### 1.1 Lo que Android permite

- **CallStyle para llamadas entrantes.** `Notification.CallStyle.forIncomingCall` existe desde API 31 (Android 12). Requiere un `Person` con nombre no vacío y dos `PendingIntent` no nulos, y muestra los botones de responder y rechazar del sistema. Fuentes: [Notification.CallStyle](https://developer.android.com/reference/android/app/Notification.CallStyle) y [guía call-style](https://d.android.com/develop/ui/views/notifications/call-style). La referencia completa no pudo leerse; el dato de API 31 viene de los resultados de búsqueda.
- **Pantalla completa (Android 14 y superiores).** Para `targetSdk` 34 o superior, la concesión por defecto se limita a apps de llamadas y alarmas. Google Play revoca la concesión por defecto a las apps que no encajan. El usuario puede concederla en ajustes, y la app puede comprobarla con `canUseFullScreenIntent()`. Fuente leída directamente: [Cambios de comportamiento de Android 14](https://developer.android.com/about/versions/14/behavior-changes-14).
- **Iniciar actividades desde segundo plano (Android 10 y superiores).** La lista oficial de excepciones incluye `SYSTEM_ALERT_WINDOW` concedido por el usuario. La pantalla completa de notificaciones **no aparece nombrada** en esa lista, así que su comportamiento debe comprobarse en dispositivo. Fuente leída directamente: [Inicio de actividades en segundo plano](https://developer.android.com/guide/components/activities/background-starts).

Conclusión: ninguno de estos mecanismos exige SAW.

### 1.2 Lo que ya hace esta app

`flutter_callkit_incoming` 3.0.0 construye la notificación nativa con Aceptar y Rechazar:

- **Android 14 y superiores (API 34):** `CallStyle.forIncomingCall` (`CallkitNotificationManager.kt:219-229`, y también en otra función de la misma clase en `:315-323`).
- **Android 12 y 13:** diseño personalizado con `RemoteViews` y `DecoratedCustomViewStyle` (`:283`). CallStyle, aunque existe desde API 31, no se usa en 31–33.
- **Pantalla completa** asociada a la actividad de llamada (`:192-194`), sin comprobar `canUseFullScreenIntent()`.
- **Solo audio:** `setIsVideo(typeCall > 0)`, con `typeCall = 0` en llamadas de voz.

ZEGO llama a esa API desde dos sitios:

- **App viva en segundo plano:** solo si SAW está concedido (`notification_manager.dart:404-416`).
- **App cerrada (mensaje FCM en el isolate de fondo):** sin comprobar SAW (`handler.call.dart:330`).

### 1.3 Dónde está el bloqueo real

Con la app viva en segundo plano, ZEGO entra en `page_manager.dart:1236-1259`. Si `showInvitationNotification` devuelve `false` porque SAW no está concedido, ZEGO intenta traer la app al frente y llama a `showNotificationOnInvitationReceived()`. Esa función inicia el tono (`:1455`) y dibuja una pantalla que no es visible desde segundo plano (`:1459`).

Para mostrar Aceptar y Rechazar sin SAW, Express tendría que tomar esa ruta. Hay dos caminos, y ninguno es seguro ni verificable en esta orden:

- **(A) Interceptar la invitación en segundo plano** y llamar ella misma a `showCallkitIncoming`.
  - ZEGO seguiría con su propio fallback (tono y pantalla), así que habría doble tono o un tono persistente.
  - La única opción de tono de ZEGO es `ZegoCallRingtoneConfig.incomingCallPath` (`config.dart:697`). Cambia el sonido; no aparece una opción documentada para desactivarlo.
  - Las acciones de la notificación nativa tendrían que enrutarse a `ZegoUIKitPrebuiltCallInvitationService().accept(...)` o `reject(...)` (`service.dart:785` y `:757`). Eso exige cablear el ciclo de vida del SDK sin dispositivos para probarlo.
- **(B) Forzar la ruta offline.** Mantener la sesión de señalización fuera del segundo plano y dejar que ZEGO envíe FCM Data, que se muestra sin compuerta (`handler.call.dart:330`).
  - Es un cambio de arquitectura: desconexión en segundo plano, impacto en batería y en fiabilidad, y dependencia de `ZEGO_RESOURCE_ID` y del PushID.
  - El comportamiento real del push de ZEGO no puede verificarse aquí, porque `zegocloud.com` no es accesible desde este entorno.

**Respuesta a la pregunta 1:** es técnicamente posible en Android, pero solo con un rediseño de la capa de llamadas. Requiere decisión de producto, que es el punto de detención previsto por la orden.

## 2. Pregunta 2: Comparación

| Criterio | A. SAW + ruta ZEGO (PR #249) | B. Nativo sin SAW (intercepción) | C. Ruta offline FCM |
|---|---|---|---|
| **Seguridad** | Concede a Express la capacidad de dibujar sobre otras apps. Es un permiso de alto riesgo por su historial de abuso en malware de superposición (fuentes generales antiguas, no de Play). El usuario lo concede a mano en ajustes. | Sin superposición. La superficie son las notificaciones y la actividad de llamada, que hoy quedan expuestas por `PERMISSION_CALL` con `normal` (§3.1). Corregible con `signature`. | Sin superposición. Depende de la entrega de FCM y de la configuración del push. |
| **Funcionamiento** | Ruta soportada por ZEGO. Con el permiso concedido, el sistema usa la notificación CallStyle o personalizada del plugin (esperado; no verificado en teléfono). Sin permiso, sigue el síntoma actual, sin regresión. | Posible, pero frágil: doble tono, enrutado de acciones y ciclo de vida del SDK. No se puede probar aquí. | En app cerrada, el código ya lo muestra sin SAW. En segundo plano dependería del push de ZEGO, que no se puede verificar aquí. |
| **Google Play** | No encontré en fuentes accesibles el criterio de declaración para SYSTEM_ALERT_WINDOW. Revisar en Play Console antes de cualquier envío (**no verificado**). | Requiere pantalla completa. Con `targetSdk` 34 o superior, la concesión por defecto se limita a apps de llamadas y alarmas. Express podría encajar como app de llamadas, pero hay que declararlo, y no está verificado. | Igual que B en cuanto a pantalla completa. Además, el push es un recurso de terceros con su propia configuración. |
| **Esfuerzo y riesgo** | Ya implementado (PR #249). Riesgo: decisión de política. | Alto: rediseño de la capa de llamadas. | Alto: cambio de arquitectura y de consumo de batería. |

**Recomendación:** mantener A como opción mínima y soportada, pero solo con una decisión explícita del propietario y la revisión de Play. No implementar B ni C sin decisión de producto y pruebas en dispositivo.

## 3. Pregunta 3: PERMISSION_CALL y READ_PHONE_STATE

Nota de método: el `flutter test` de la orden anterior re-resolvió dependencias (unos 225 paquetes respecto a la caché previa). Por eso repetí el escaneo de manifests y de dependencias Maven sobre el paquete resuelto actual. El resultado es el mismo.

### 3.1 PERMISSION_CALL

- **Declaración** (`flutter_callkit_incoming-3.0.0/android/src/main/AndroidManifest.xml`): permiso `${applicationId}.PERMISSION_CALL` con `protectionLevel="normal"` (línea 19). Componentes exportados que lo exigen: la actividad de llamada (`:30-34`), el receptor (`:48-49`) y el servicio en primer plano (`:61-63`).
- **Riesgo:** con `normal`, cualquier app que declare ese nombre recibe el permiso automáticamente. Así, otras apps podrían abrir la pantalla de llamada o enviar acciones con datos falsos. Es un problema del plugin, no de ZEGO.
- **Quién los invoca hoy:** solo la propia app.
  - `PendingIntent` creados por la app (`CallkitNotificationManager.kt:192-196`, `:228-229`, `:322-323`).
  - Envíos desde el mismo proceso (`CallkitNotificationManager.kt:826-834` y `CallkitIncomingActivity.kt:340`).
  - Con `signature` siguen autorizados, porque tienen el mismo UID y la misma firma.
- **Propuesta:** `android:protectionLevel="signature"` mediante un override en `build-android.yml` (`xmlns:tools` y `tools:replace="android:protectionLevel"`).
- **No aplicada:** no hay Android SDK en el entorno (solo Gradle), así que no puede comprobarse la fusión del manifest. Además, cambia la protección de componentes de llamada y necesita prueba física: aceptar y rechazar desde la notificación, pantalla completa y app cerrada.

### 3.2 READ_PHONE_STATE

- Presente en el APK QA 1.6.2+140 (auditoría de la ORDEN 003).
- Escaneo sobre los paquetes resueltos en esta sesión: ningún manifest de librerías Flutter lo declara. `zego_express_engine_for_uikit` 3.25.0+1 tampoco.
- **Candidatos** (no verificables aquí):
  - ZEGO: `im.zego:zim:2.29.0`, `im.zego:zpns:2.8.1`, `im.zego:uikitreport:0.6.1`. `storage.zego.im` está bloqueado.
  - Google: `com.google.firebase:firebase-messaging:21.1.0` (dependencia de zpns), `play-services-ads`, `ads-mobile-sdk` y `user-messaging-platform` (de `google_mobile_ads`, que está resuelto pero no declarado en `pubspec.yaml`), `play-services-location` y `play core`. Las descargas desde `maven.google.com` fueron rechazadas por el proxy (403 al abrir el túnel).
- **Brecha verificada:** el bloque de permisos prohibidos de `build-android.yml` (a partir de `MANIFEST=android/app/src/main/AndroidManifest.xml`, línea 514) solo busca en el manifest de la app. No detecta permisos que aportan las librerías.
- **Riesgo de retirarlo:** `tools:node="remove"` sin conocer el origen puede romper el seguimiento de estado de llamadas de ZEGO o el SDK de anuncios. No se recomienda.
- **Recomendación:** generar el informe del fusionador (`manifest-merger-*-report.txt`) en un job de diagnóstico que **no** cree release ni publique nada. Decisión del propietario.

## 4. Pregunta 4: Estado de CI

Head `0f9e6e5` (PR #249). Los cinco checks terminaron con éxito:

| Check | Resultado | Run |
|---|---|---|
| validate | success | 38683670764 |
| Shared Flutter checks and production-format Web | success (finalizó 04:55:33 UTC) | 38683670679 |
| guard | success | 38683670741 |
| change-inventory | success | 38683670701 |
| Vercel Preview Comments | success | — |

Re-ejecución tras el commit de este informe: ver §6.

## 5. Cambios de código

**Ninguno.** Motivos:

1. La alternativa sin SAW exige decisión de producto (B o C).
2. PERMISSION_CALL y READ_PHONE_STATE requieren build de Android o dispositivo para verificarse.
3. No se encontró ningún error propio en PR #249 que cumpla ambos requisitos.

Este commit solo añade este informe.

## 6. Estado final y verificación

- **Pruebas:** sin cambios de código en esta orden. Las 12 pruebas de voz y ZEGO del commit `0f9e6e5` pasan (verificado en la orden anterior).
- **CI en el head `1050bacc`** (commit de este informe): el estado combinado es `success`. El único check que se ejecutó fue `Vercel Preview Comments` (run `116258212492`, success). Los checks de código (validate, guard, Shared Flutter checks, change-inventory) no se volvieron a ejecutar, porque el commit solo cambia `docs/reports/`. Su resultado válido es el de `0f9e6e5` (§4).
- **Despliegue de vista previa de Vercel:** la integración de Vercel creó además un despliegue de vista previa automático para el PR (contexto `Vercel`, estado `success`, «Deployment has completed»). No lo solicité en esta orden. `AGENTS.md` prohíbe webs de prueba adicionales, así que el propietario debe decidir si esa integración debe mantenerse para este repositorio.

## 7. Bloqueos y lo no verificado

- Sin dispositivos Android.
- Sin Android SDK: no hay build de APK ni comprobación del manifest fusionado.
- Inaccesibles desde el entorno: `docs.zegocloud.com`, `support.google.com` (política de Play), `source.android.com`, `storage.zego.im` y `maven.google.com` (descargas de AAR, 403).
- **No verificado:** el comportamiento real de pantalla completa y de CallStyle en un teléfono; los criterios de Play para SAW y para pantalla completa; el origen de READ_PHONE_STATE; el comportamiento del push offline de ZEGO.

## 8. Decisiones para el propietario

1. ¿Aceptar SAW (PR #249), con el diálogo al iniciar la voz y la revisión de Play? Es hoy la única vía soportada para mostrar controles en segundo plano.
2. ¿O aceptar que las llamadas en segundo plano no muestren controles (comportamiento actual)?
3. ¿Investigar B (rediseño nativo) o C (ruta FCM)? Requiere presupuesto técnico y pruebas en dispositivo.
4. ¿Autorizar un PR aparte para `PERMISSION_CALL` con `signature`?
5. ¿Autorizar un job de diagnóstico que genere el informe del fusionador sin publicar release?
6. Confirmar en Play Console las declaraciones de pantalla completa y de SAW antes de cualquier envío a Play.
7. ¿Mantener la integración de Vercel que crea vistas previas automáticas por PR? `AGENTS.md` prohíbe webs de prueba adicionales (§6).

## 9. Fuentes

- Cambios de comportamiento de Android 14: https://developer.android.com/about/versions/14/behavior-changes-14
- Inicio de actividades en segundo plano: https://developer.android.com/guide/components/activities/background-starts
- Notification.CallStyle: https://developer.android.com/reference/android/app/Notification.CallStyle
- Guía de call-style: https://d.android.com/develop/ui/views/notifications/call-style
- Código local del SDK y del plugin (caché de pub): `zego_uikit_prebuilt_call` 4.24.4, `zego_plugin_adapter` 2.14.2 y `flutter_callkit_incoming` 3.0.0.
