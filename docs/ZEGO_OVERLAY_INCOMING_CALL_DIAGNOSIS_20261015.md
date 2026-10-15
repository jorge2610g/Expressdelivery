# Llamadas de voz entrantes en segundo plano (Android): diagnóstico y corrección

**Fecha:** 15-10-2026 · **Base:** `origin/main` 95e22e27 (1.6.2+140) · **Orden técnica:** 004 (ZEGO / Android, P0)

**Estado:** PR en borrador, **no fusionado**. Sin APK, sin despliegue, sin cambios en Producción ni en Supabase. La causa está demostrada en el código del SDK y la corrección tiene pruebas automáticas. **Nada de esto está verificado todavía en teléfonos reales** (ver §7).

## 1. Síntoma

Con Express minimizada o con la pantalla bloqueada, el teléfono suena al llegar una llamada, pero no aparece notificación ni pantalla con Aceptar y Rechazar.

## 2. Causa raíz demostrada en el código

Fuentes verificadas en el paquete instalado: `zego_uikit_prebuilt_call` 4.24.4, `zego_plugin_adapter` 2.14.2, `flutter_callkit_incoming` 3.0.0 y `permission_handler_android` 13.0.1 (caché local de pub, sin fuentes de terceros).

| # | Qué ocurre | Dónde |
|---|---|---|
| 2.1 | Con la app en segundo plano, ZEGO muestra la llamada nativa (notificación y pantalla de llamada) **sólo si** `Permission.systemAlertWindow` está concedido. | `notification_manager.dart:139-146` y `:404-416` |
| 2.2 | Si no está concedido, ZEGO intenta traer la app al frente y llama a `showNotificationOnInvitationReceived()`. Esa función **inicia el tono** y dibuja la pantalla dentro de Flutter, que no es visible desde segundo plano. | `page_manager.dart:1249-1259` y `:1451-1459` |
| 2.3 | Express no puede conceder ese permiso: `SYSTEM_ALERT_WINDOW` no está en el manifest generado por `build-android.yml` ni en el APK QA 1.6.2+140 (auditoría del ORDEN 003). Sin declaración en el manifest, la opción no aparece en Ajustes. | `build-android.yml` (bloque de permisos); auditoría del APK |
| 2.4 | La configuración de inicio de voz sólo pedía micrófono. ZEGO no solicita el permiso de superposición salvo que aparezca en `permissions`. | `lib/private_voice_call.dart` (dos rutas de inicio); `CHANGELOG.md` del SDK, entrada 4.16.7 |
| 2.5 | Android 10 y superiores bloquean iniciar actividades desde segundo plano. Una de las excepciones es `SYSTEM_ALERT_WINDOW` concedido por el usuario. | Documentación oficial: `developer.android.com/guide/components/activities/background-starts`, excepción 4 |

**Resultado:** suena, pero no hay pantalla. Esto explica el síntoma completo.

**Descartado en el código:**
- *Notificaciones y canal de llamada:* ZEGO pide el permiso de notificaciones al iniciar y crea el canal de llamada con importancia máxima (`PluginNotification.java:231`). No es el bloqueo principal.
- *Mensaje FCM con la app cerrada:* en esa ruta, `handler.call.dart:330` llama directamente a `showCallkitIncoming`, sin la compuerta del punto 2.1. Con la app abierta, el mensaje pasa al isolate principal (`handler.call.dart:310`) y **sí** aplica la compuerta.
- *Pantalla completa en Android 14 y superiores:* ZEGO pide el permiso especial (`service.dart:465`). Cambia la forma de la pantalla (completa o emergente), no si la llamada aparece.

**Por qué #246 no bastó:** añadió `USE_FULL_SCREEN_INTENT`, `singleInstance`, `showOnLockedScreen` y `showOnFullScreen`. Son necesarios para la pantalla de llamada, pero no resuelven la compuerta de superposición.

## 3. Corrección en este PR (mínima)

1. **`.github/workflows/build-android.yml`**: declara `android.permission.SYSTEM_ALERT_WINDOW` en el manifest generado (línea 346) y lo verifica con un `grep` (línea 521). Un `android/` regenerado no puede perderlo.
2. **`lib/private_voice_call.dart`**: añade `ZegoCallInvitationPermission.systemAlertWindow` en las dos rutas de inicio (líneas 440 y 755). ZEGO muestra su diálogo y abre Ajustes. No cambia la lógica de llamadas.
3. **Textos en español** del diálogo (líneas 327-328): «Permitir que Express muestre llamadas sobre otras aplicaciones». El título anterior, «Permiso de micrófono», sólo lo usaba ese diálogo, según el SDK. El micrófono no cambia.
4. **`test/android_voice_permission_contract_test.dart`**: comprueba la declaración, la guarda y las dos rutas.

**No cambia:** PERMISSION_CALL, READ_PHONE_STATE, la lógica de Taxi y Envíos, backend, Supabase, zonas, pagos ni Delivery.

## 4. Decisión que el propietario debe tomar antes de fusionar

`docs/ZEGO_BACKGROUND_CALLS_RUNBOOK_20261014.md`, punto 6, dice: «**No añadir `SYSTEM_ALERT_WINDOW` automáticamente**: requiere política/permisos del sistema y QA del paquete Play». Este PR sí lo añade, de forma explícita y revisable, porque sin ese permiso la llamada en segundo plano no puede mostrar sus controles (§2).

Antes de fusionar o generar una APK hace falta:
- una decisión explícita del propietario sobre este permiso;
- revisar la política de Google Play para permisos de superposición antes de cualquier envío a Play;
- aceptar que el diálogo aparece al iniciar la voz (§6, punto 2).

Si no se acepta, las llamadas en segundo plano seguirán sin controles, como hoy.

## 5. Errores de ZEGO observados

- **301003002 = `invitationCancelError`** (`zego_plugin_adapter/lib/src/signaling/errors.dart:99`): fallo al **cancelar** una invitación. No es un fallo de envío (`301003001`, línea 96) ni prueba de caída de internet. Sin registros del dispositivo no puede saberse por qué falló la cancelación.
- **`call_cooldown` (429):** el backend bloquea durante 30 s una nueva llamada del mismo pasajero al mismo viaje si hay un intento que no quedó `failed` (`supabase/functions/zego-call/index.ts:263-275`). La app muestra «Ya intentaste llamar hace poco. Espera unos segundos e inténtalo de nuevo.» (`lib/voice_call_error_message.dart`) y no reintenta sola. Sin cambios: ya tiene pruebas.
- El mensaje genérico «Comprueba tu conexión» aparece cuando el error no se reconoce. No se debe atribuir a internet sin evidencia.

## 6. Riesgos residuales

1. **Hasta que el usuario conceda «Mostrar sobre otras aplicaciones», vuelve el síntoma** (suena sin pantalla). Es el comportamiento del SDK.
2. **El diálogo aparece al iniciar la voz**, para cualquier usuario con voz habilitada (Taxi y Envíos). Es un cambio visible; no interrumpe el servicio.
3. Si el usuario lo rechaza, el diálogo se repite en el siguiente inicio, porque el SDK no recuerda la negativa.
4. En Android 14 y superiores, la pantalla completa requiere un permiso especial que el usuario puede revocar. Sin él, la llamada aparece como notificación emergente con botones.
5. Un canal de notificación ya creado con importancia baja no se corrige por código. Hay que restablecer la configuración de notificaciones de la app en el teléfono.
6. **App cerrada:** depende de `ZEGO_RESOURCE_ID` y del PushID (runbook, puntos 2 a 5). No verificado en esta sesión.
7. **READ_PHONE_STATE** aparece en el APK, pero ninguna librería de pub lo declara. El origen probable es un AAR de ZEGO (`im.zego:zim`, `im.zego:zpns`, `im.zego:uikitreport`) o de Google. No se pudo descargar el AAR porque `storage.zego.im` no es accesible desde este entorno. **Propuesta:** que el CI guarde el informe del fusionador de manifiestos (`manifest-merger-release-report.txt`) para ver qué librería lo aporta. No retirarlo sin prueba física de llamadas.
8. **PERMISSION_CALL con `protectionLevel="normal"`** (manifest de `flutter_callkit_incoming`): cualquier aplicación que lo declare recibe el permiso automáticamente. Así, los componentes exportados que lo exigen (actividad de llamada entrante, receptor y servicio) quedan abiertos a otras apps. **Propuesta:** `signature`, mediante `tools:replace` en el manifest. No se implementa aquí: protege componentes de llamada y necesita prueba física. Los intentos desde las notificaciones propias seguirían funcionando, porque van firmados por la misma app.
9. Nada de lo anterior está verificado en teléfonos reales.

## 7. Plan de pruebas físicas (Taxi y Envíos)

**Requisitos:** dos teléfonos Android con Express. Una APK sólo si el propietario lo ordena. Cuentas de prueba de pasajero y conductor. En cada teléfono: «Mostrar sobre otras aplicaciones» activado, notificaciones permitidas, pantalla completa permitida (Android 14 o superior), batería sin restricciones y sin «No molestar».

| Escenario | Resultado esperado | Registro |
|---|---|---|
| A. App abierta (receptor en primer plano) | Pantalla de llamada dentro de Express; aceptar; audio en ambos sentidos; colgar | `private_voice_calls.status` y `answered_at` |
| B. App minimizada | Notificación o pantalla de llamada con Aceptar y Rechazar. No puede haber sonido sin pantalla | Hora de aparición |
| C. Pantalla bloqueada | Pantalla o notificación sobre el bloqueo; aceptar; audio | Hora de aparición |
| D. App cerrada (forzar cierre) | Llamada nativa si el fabricante lo permite; si no, documentarlo | Hora y fabricante |
| E. Rechazar | El emisor ve «rechazada»; no queda sonido | — |
| F. Cancelar desde el emisor antes de contestar | El receptor deja de sonar. Si queda sonando, anotar el código de error | Código 301003002 si aparece |
| G. Sin permiso de superposición (control negativo) | Debe reproducir el síntoma; confirma la causa | Captura de pantalla |
| H. Dos intentos seguidos | El segundo queda bloqueado con mensaje de espera (`call_cooldown`) | Mensaje mostrado |
| I. Corte de red y reconexión | Tras reconectar, una llamada nueva funciona; no quedan registros fantasma `answered` | — |
| J. Pasajero a conductor y conductor a pasajero | Igual en ambos sentidos, en Taxi y en Envíos | — |

**Criterio para declarar corregido:** A a E y J pasan en dos teléfonos distintos (uno con Android 14 o superior y otro anterior), con el permiso concedido. Registrar versión, modelo y versión de Android. No incluir correos, tokens ni identificadores privados en el informe.

## 8. Decisiones pendientes del propietario

1. Aceptar o rechazar el permiso «Mostrar sobre otras aplicaciones» y el diálogo al iniciar la voz (§4).
2. Autorizar las pruebas físicas y, sólo después, la orden «genera APK». En esta orden **no** se generó APK.
3. Cambiar PERMISSION_CALL a `signature` (§6, punto 8).
4. Revisar el origen de READ_PHONE_STATE con el informe del fusionador (§6, punto 7).
5. Actualizar el punto 6 del runbook según la decisión.

## 9. Verificación realizada

- `flutter test` (sin `pub get`): `android_voice_permission_contract_test`, `voice_call_error_message_test`, `zego_failed_call_cooldown_source_test`, `zego_native_incoming_reconnect_source_test`, `zego_token04_nonce_source_test` y `voice_web_sdk_contract_test`: 12 de 12 pasan.
- `flutter analyze` sobre `lib/private_voice_call.dart` y el test: sin errores nuevos. Dos avisos previos, en líneas no modificadas (un import sin uso y el campo `_zegoUserName` sin uso).
- `actionlint` sobre `build-android.yml`: sin hallazgos, antes y después del cambio.
- `.github/scripts/check_single_app_contract.py`: PASS.
- **No** se ejecutó el workflow `build-android.yml`, porque genera un release público.
