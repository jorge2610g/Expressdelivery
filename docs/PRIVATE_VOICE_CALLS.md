# Llamadas privadas Express

## Preview 1.6.0+145

- Proveedor RTC: ZEGOCLOUD.
- Solo audio, 1 a 1.
- Los números telefónicos no se comparten entre pasajero y conductor.
- Ambos participantes deben tener el teléfono verificado.
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
