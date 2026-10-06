# Llamadas privadas Express

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
