# Llamadas privadas Express

## Pulido Preview 1.6.0+155

La llamada privada mantiene ZEGOCLOUD 1:1 y solo audio, pero +155 elimina la apariencia de videollamada:

- cámara deshabilitada;
- barra superior oculta;
- avatar/nombre y duración visibles;
- barra inferior limitada a **Micrófono / Altavoz / Colgar**;
- textos de llamada e invitación en español;
- permisos limitados al micrófono;
- OTP sigue siendo independiente: la llamada se autoriza por viaje activo, participantes y canal.

## Preview 1.6.0+145

- Proveedor RTC: ZEGOCLOUD.
- Solo audio, 1 a 1.
- Los números telefónicos no se comparten entre pasajero y conductor.
- El OTP/verificación telefónica se mantiene como función de cuenta, pero **no condiciona la llamada privada**.
- La llamada solo puede prepararse para un viaje activo donde ambos usuarios sean participantes.
- El ServerSecret permanece únicamente en Supabase Edge Functions.
- Producción no se promueve automáticamente; esta versión se valida primero en Preview.


## Build de validación

La primera base nativa utilizable para llamadas privadas es Preview 1.6.0+146.


## Corrección Preview 1.6.0+151

Durante la validación manual de +151 se detectó que las tarjetas principales de viaje activo en `video_style_home.dart` todavía llamaban a `callExpressNumber(...)`, que construye un URI `tel:`. En Android esto abría el selector externo de aplicaciones (por ejemplo Teléfono/Zoom) y evitaba por completo la ruta privada ZEGOCLOUD.

Corrección aplicada:

- pasajero → conductor en viaje activo usa `ExpressPrivateVoiceCall.instance.startTripCall(...)`;
- conductor → pasajero en viaje activo usa `ExpressPrivateVoiceCall.instance.startTripCall(...)`;
- los números siguen ocultos entre las partes;
- el botón de viaje activo no debe abrir `tel:`, Teléfono, Zoom ni otra app externa;
- delivery conserva por ahora su comportamiento separado y no forma parte de esta corrección;
- commit de app: `df5959499e58cdf258372baa81e2321fd3e3e32b`;
- QA agrega un guard que bloquea el candidato si las dos tarjetas de viaje activo dejan de usar `ExpressPrivateVoiceCall`; commit `169a32387c6101a8b7169018d941d3c6dcf7e9f9`.

Validación esperada para considerar el arreglo correcto:

1. al tocar **Llamar** desde la tarjeta principal del viaje activo, la app invoca `zego-call` con acción `prepare`;
2. se crea un registro en `private_voice_calls` para el viaje;
3. se envía la invitación ZEGOCLOUD;
4. Android no muestra selector externo de Teléfono/Zoom.


## Nueva base Preview 1.6.0+152

El fix de +151 se intentó publicar como patch Shorebird. Shorebird lo rechazó por diferencias nativas/DEX detectadas en el build Android, incluyendo componentes de ZEGO, Firebase Messaging, Didit y clases registradas por Android.

Decisión oficial:

- no forzar `--allow-native-diffs`;
- no mover el gate;
- no certificar QA sobre una identidad distinta;
- crear una nueva base Preview con el fix incorporado.

Candidato:

- versión: `1.6.0+152`;
- commit de creación de base/pinning de dependencias: `c5f397c8ce617b97fb1f3b723f38c6b00c6835c3`;
- Preview publica solamente `app-release.apk`;
- Producción permanece intacta.

Antes de considerar +152 lista se deben confirmar:

1. Shorebird base release en success;
2. tag `preview-shorebird-v1.6.0-build152`;
3. APK publicado;
4. `app_release_gate` con la misma versión/build/SHA;
5. QA sobre el mismo SHA;
6. prueba manual donde **Llamar** abra ZEGOCLOUD y nunca Teléfono/Zoom.


## Corrección de invitaciones ZEGOCLOUD · Preview 1.6.0+153

Regla de producto confirmada:

- OTP permanece disponible y puede seguir activándose/desactivándose desde la configuración correspondiente;
- la llamada pasajero ↔ conductor **no depende** de `phone_verified_at`;
- la autorización de llamada depende del viaje activo, el canal correcto y que caller/callee sean exactamente los participantes asignados;
- los números reales siguen ocultos.

Corrección de señalización:

- se registra `useSystemCallingUI([ZegoUIKitSignalingPlugin()])` antes de `runApp`, como exige el flujo de invitaciones de ZEGOCLOUD;
- `MaterialApp` y el servicio de invitaciones comparten exactamente la misma instancia de `navigatorKey`;
- se reutiliza una única instancia del signaling plugin para el system calling UI y para `init`;
- se agregan eventos de diagnóstico para inicialización, envío, recepción y errores ZEGO;
- si `send()` vuelve a devolver `false`, el log registra estado de señalización, inicialización, system calling UI y presencia de Resource ID.

Este cambio es Dart-only sobre la base +153 y debe intentarse primero como patch Shorebird. Solo se crea otra APK base si Shorebird detecta una diferencia nativa real.


## Nueva base Preview 1.6.0+154

El cambio de señalización de +153 se intentó publicar primero como patch Shorebird. El build completó, pero Shorebird rechazó el patch por diferencias nativas/DEX.

Evidencia del rechazo:

- `base/dex/classes7.dex` distinto;
- diferencias en ZIM/ZEGOCLOUD;
- `GeneratedPluginRegistrant`;
- Firebase Messaging;
- Kotlin/coroutines;
- Didit SDK.

Decisión oficial:

- no usar `--allow-native-diffs`;
- no mover el gate con un patch no publicado;
- crear Preview **1.6.0+154** como nueva base APK;
- mantener Producción sin cambios.

La +154 conserva la lógica preparada en +153: OTP sigue existiendo pero no decide si se puede llamar; la llamada se autoriza por viaje activo, participantes y canal; ZEGOCLOUD registra `useSystemCallingUI` antes de `runApp`, comparte el mismo `navigatorKey`, reutiliza una sola instancia de signaling y registra evidencia si la invitación falla.


## 2026-10-06 · Error ZEGO 50013: userID demasiado largo

La prueba manual de Preview 1.6.0+154 dejó evidencia exacta en `app_error_logs`:

- `ZEGOCLOUD invitation error`;
- código UIKit `301001003`;
- excepción ZIM `50013`;
- mensaje: `userid length limit err`;
- signaling quedó `disconnected`, por lo que `send()` devolvió `false`.

Causa raíz:

- Express generaba el ID ZEGO como `u_` + UUID sin guiones;
- UUID sin guiones = 32 caracteres;
- prefijo `u_` = 2 caracteres extra;
- resultado = 34 caracteres, fuera del límite aceptado por ZIM.

Corrección:

- `zegoUserId()` usa ahora únicamente el UUID sin guiones, exactamente 32 caracteres;
- sigue siendo determinista por usuario;
- no expone número telefónico ni correo;
- no cambia la autorización: solo los participantes del viaje activo pueden llamar;
- es un cambio backend de `zego-call`, por lo que **no requiere otra APK ni patch Shorebird**;
- la misma Preview +154 puede volver a probar la llamada después del despliegue backend.


## PENDIENTE · Preview 1.6.0+155 · UI de llamada de audio en español

Solicitud del propietario reservada para la siguiente versión Preview **+155**:

- traducir toda la interfaz visible de la llamada al español;
- reemplazar textos predeterminados de ZEGO como `Calling...`, `Microphone ON/OFF` y `Speaker ON/OFF`;
- eliminar/ocultar el recuadro flotante del participante que visualmente parece una videollamada;
- conservar la llamada estrictamente **solo audio**;
- diseño objetivo: avatar/nombre al centro, duración y controles claros **Micrófono · Altavoz · Colgar**;
- mantener números telefónicos ocultos y autorización únicamente entre pasajero y conductor del viaje activo;
- no modificar OTP ni volver a vincular OTP con el permiso de llamada.

**Estado:** PENDIENTE DE IMPLEMENTAR en +155. No marcar como terminado hasta validación manual en ambos roles.
