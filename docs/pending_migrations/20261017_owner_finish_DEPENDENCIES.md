# Dependencias de servidor de las correcciones finales (PR #262)

Estado: **solo documentación. Nada de esto está desplegado ni aplicado.**
No ejecutar migraciones, Edge Functions ni cambiar `app_settings` sin autorización expresa del propietario.

## Ítem 3 — vencimiento de 30 s

- Cliente (APK): la tarjeta flotante y el popup usan `min(vencimiento del servidor, 30 s)`. No muestran una vigencia ficticia.
- Servidor: `app_settings.offer_timeout_seconds = 20` (lectura del 17-oct-2026). El trigger `trg_driver_offer_deadline` y `driver_offer_expires_at` fijan `expires_at` con ese valor.
- Para 30 s reales hay que cambiar el setting global. Eso afecta a producción: **requiere autorización separada**.
- Alternativa acotada a QA: setting por entorno en `admin_environment_config` leído por `driver_offer_expires_at`. Requiere migración: **propuesta, no aplicada**.
- Mientras tanto la aceptación se rechaza si `expires_at` ya pasó (`isRideOfferExpiredAt`), por lo que no se puede aceptar tras la expiración del servidor.

## Ítem 2 — búsqueda vencida del pasajero

- Ya existen en servidor: `renew_ride_request(p_ride_request_id, p_proposed_fare)` y `cancel_ride_request(p_ride_request_id, p_reason)`.
- Cliente corregido: el diálogo «¿Seguimos buscando?» se evalúa cada segundo (antes solo al llegar un refresco).
- Riesgo residual: `passenger_home_state_v2` cancela búsquedas vencidas hace más de 30 s al cargar el estado. Si la app está en segundo plano al vencer, la solicitud puede retirarse antes de mostrar las opciones.
- Propuesta (no aplicada): ampliar la gracia o marcar la búsqueda como `awaiting_passenger_decision` mientras el pasajero decide.

## Ítem 5 — push duplicado con la ventana flotante

- Hoy el servidor envía el mensaje con bloque `notification`; el sistema lo muestra aunque la ventana flotante ya esté activa.
- Cliente: al mostrarse la ventana, la notificación local de la misma oferta se retira (`cancelOfferNotifications`, implementado en 2886269). La notificación del sistema del servidor no se puede suprimir desde el cliente.
- Para eliminarla por completo hace falta enviar solo datos a los tokens que confirmaron el overlay activo. La autorización para desplegar ese cambio fue dada por el propietario el 2026-10-21; el despliegue y sus verificaciones quedan registrados en `docs/BUILD_142_CHANGELOG.md`.

## Ítem 11 — invalidación de ofertas

- Cliente: al fallar la aceptación con «no disponible», la oferta sale de la lista, se cierra el popup, se detienen sonido y tarjeta flotante.
- Pendiente de servidor: retirar la notificación push correspondiente cuando la solicitud se vence, cancela o adjudica (requiere el mismo cambio que el ítem 5).

## Ronda de correcciones del 17-oct (23:01 UTC) — estado de dependencias

- **Defecto 1 (push + ventana duplicadas):** el heads-up del sistema lo genera el payload del servidor con bloque `notification`. El cliente solo puede retirarlo después de mostrar la ventana. El cambio de `express-push-dispatch` ahora envía solo datos a tokens con overlay activo y comprobación reciente; tokens sin estado vigente conservan la push normal. Consultar `docs/BUILD_142_CHANGELOG.md` para el resultado de despliegue.
- **Defecto 6 (cámara):** el centrado en el área visible requiere desplazar la cámara por la altura real del bottom sheet en las llamadas `move`/`fitCamera` del pasajero y del conductor. Pendiente de validación visual en emulador de ambos roles.
- **APK 142:** la base rechaza `build_jobs` con versionCode 142 porque `app_release_gate.next_production_build_number = 141` (`enforce_android_store_build_sequence`). No se modificó la regla ni el gate: requiere decisión del propietario.
