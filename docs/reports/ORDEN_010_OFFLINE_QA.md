# ORDEN 010 — Cierre de seguridad y estabilidad de PR #250

- Rama: `perf/map-continuity-offline-20261015` (PR #250, borrador contra `main`).
- Alcance: mapa, conexión, caché por cuenta, cancelaciones y pagos pendientes.
- Fuera de alcance y no tocado: ZEGO, flujos económicos del backend, migraciones, credenciales, APK, despliegue, merge de #248/#249 o `main`.

## 1. Mapa: el tiempo de espera de 6 s no retira el mapa anterior

| Punto | Comportamiento | Evidencia |
|---|---|---|
| Cambio de fuente (OSM ↔ Mapbox) | La capa saliente se conserva hasta que la nueva fuente entrega un tile real (ancho > 1 px). Un tile de 1×1 (fallo silenciado) no cuenta. | `lib/map_tile_handover.dart` (`ExpressFirstRealTileImageProvider`, `isRealTileWidth`), test `map_tile_handover_test.dart` |
| Espera sin tiles | Ningún temporizador libera la capa anterior. Esperar cualquier tiempo sin tile real deja el mapa anterior visible. | Test «no amount of waiting releases the old layer» |
| Cambios encadenados | `begin()` guarda la capa visible con `_outgoingMapbox ??= _activeMapbox`; un cambio intermedio no sustituye la capa visible. Solo el tile del generation actual cierra el relevo. | Tests «second switch keeps…», «A to B to A…» |
| Atribución | Sigue a las teselas en pantalla, no al valor objetivo. | `ExpressMapProvider.attributionUsesMapbox`, test «switch away from Mapbox keeps Mapbox attribution» |
| Cliente HTTP por capa | Cada capa de Mapbox usa su propio cliente y lo cierra al retirarla (antes había fuga). | `ExpressHandoverTileProvider.dispose()`, `_MapboxCountingHttpClient` |
| Caché de teselas | Se conserva (`MapCachingProvider`, 350 MB, 12 h). No contiene datos personales ni se borra al cambiar de cuenta. | `ExpressMapProvider.offlineTileCache` |
| Nuevas teselas | No se añade ningún proveedor ni dependencia. | Sin cambios en `pubspec.yaml` |

Conclusión: no existe ningún camino en el que un tiempo de espera retire la capa anterior sin una imagen válida nueva.

## 2. Detector de conexión

Cambios en `lib/offline_status.dart`:

- Nuevo `resetForAccountChange()`: cancela el temporizador, elimina la sonda y las fechas de última respuesta válida, y vuelve a `online`. Se usa al cerrar sesión o cambiar de cuenta.
- Se mantienen: 3 fallos de red para `offline`, backoff 2/4/8/16/30 s, `onAppResumed`, `recordSuccess` solo tras respuesta real.
- Un error de datos del servidor cuenta como conexión existente (no cambia a offline).

Tests nuevos en `test/offline_status_test.dart`:

- Fallo de red → offline → reset: estado `online`, `lastValidAt` nulo, temporizador anterior cancelado, sin sondas posteriores.
- Recuperación: sonda correcta devuelve `online` y registra la hora.

No se añadió `connectivity_plus` (ver §7).

## 3. Confirmaciones sin respuesta del servidor

| Acción | Antes | Ahora |
|---|---|---|
| Avance de viaje del conductor (`_advanceTrip`, llegada, espera, inicio) | El estado optimista se aplicaba antes de la llamada RPC. | El estado solo cambia en `onSuccess`. Mientras tanto se muestra el estado anterior con el indicador de proceso. En error se relee el servidor (`_refreshDriverHome`) en vez de revertir a una copia local. |
| Pago con billetera (`_payWithWallet`) | Un error de red podía dejar reintentar el mismo plan y cobrar dos veces. | Si el resultado es incierto (red, timeout o respuesta sin `provider = wallet`), el plan queda bloqueado hasta recargar la pantalla y se relee la suscripción. Los rechazos definitivos (saldo insuficiente, moneda) no bloquean. |
| Pre-chequeo de billetera (`ensure_country_wallet_v2`) | Sin límite de espera. | Límite de 15 s; si falla, el mensaje neutral existente se mantiene. |

Cancelaciones (revisión sin cambios de servidor): `cancel_ride_request` y `cancel_trip` ya son idempotentes en servidor (devuelven éxito si ya estaban canceladas). El cliente sigue permitiendo cancelar en estados recuperables. No se añadió bloqueo adicional.

## 4. Caché y cuentas

Nuevo `lib/core/account_device_cache.dart`:

- Claves globales del dispositivo que contienen ubicación o datos de cuenta: `express_last_valid_location_v1`, `express_processed_push_keys_v1`.
- Prefijos por cuenta: `express_account_bootstrap_v1_`, `express_passenger_landing_v1_`.
- Marcador de cuenta `express_device_account_uid_v1`.
- Conservado a propósito: `express_mapbox_quota_state_v1` (cuota, no personal), `runtime_config_v1`, caché de teselas.

Nuevo `lib/account_memory_reset.dart` (`forgetAccountMemory`): resetea el monitor, la última posición en memoria, el estado precargado del pasajero y las rutas en memoria.

Cableado:

- `lib/mobile_main.dart`: antes de `runApp` (si el arranque fue bien) se llama a `switchAccountDeviceCachesIfNeeded(uid)`. En `signedOut` se llama a `clearAccountDeviceCaches`. En `signedIn` se llama a `switchAccountDeviceCachesIfNeeded`.
- `lib/web_main.dart`: mismo cableado en su listener de autenticación (usa las mismas preferencias).

Tests: `test/account_device_cache_test.dart` (6): cierre de sesión borra ubicación, push y cachés por cuenta; conserva cuota y configuración; cambio de cuenta borra la caché anterior; misma cuenta conserva; `uid` nulo no hace nada; sin marcador se reconstruye.

Limitación conocida: si una cuenta B entra sin pasar por `signedOut` (p. ej. sesión restaurada), la caché de A se borra en `signedIn` o en el arranque, pero la pantalla puede leer antes de que termine esa operación asíncrona. Se documenta como riesgo residual.

## 5. Tests de esta orden

| Archivo | Casos | Resultado |
|---|---|---|
| `test/map_tile_handover_test.dart` | 11 | OK |
| `test/offline_status_test.dart` | 17 (15 previos + 2 nuevos) | OK |
| `test/express_offline_banner_test.dart` | 5 | OK |
| `test/account_device_cache_test.dart` | 6 | OK |
| `test/orden010_contract_test.dart` | 5 | OK |
| `test/overlay_discrete_contract_test.dart`, `test/map_route_cache_test.dart`, `test/passenger_offline_and_guard_contract_test.dart` | previos | OK |
| Suite completa `flutter test --no-pub` | 187 | **All tests passed** |

Análisis: `flutter analyze --no-pub` sobre los archivos cambiados: 0 errores. Los avisos que quedan (`unused_import`, `unnecessary_non_null_assertion`, `unused_local_variable` en `video_style_home.dart`, `unused_field` en `express_service.dart`, etc.) ya existían antes de esta orden y están en líneas no tocadas.

## 6. Propuestas documentadas (NO ejecutadas)

Requieren autorización del propietario. Ninguna se ha aplicado.

1. **Idempotencia de cobro con billetera:** clave de idempotencia (`idempotency_key`) en `pay_driver_subscription_with_country_wallet` y tabla `driver_subscription_payments`. Hoy la migración `20261012120500` inserta una fila nueva y debita en cada llamada; un reintento real del servidor puede debitar dos veces. Requiere migración y revisión económica.
2. **Índice único en `driver_offers`** (`ride_request_id`, `driver_id`): el `upsert` de `createRideOffer` usa ese `onConflict`, pero no encontré la restricción en las migraciones del repositorio.
3. **Pagos pendientes de proveedor (Mercado Pago / QR):** reutilizar la preferencia de la Edge Function en vez de crear otra, y cancelar la preferencia anterior. Requiere cambios en `driver-subscription-payments` (backend económico, fuera de alcance).
4. **`service_cancel_driver_subscription_payment`:** la RPC citada no aparece en las migraciones revisadas; hay que confirmar si existe en producción antes de usarla.
5. **Calificaciones (`submitRating`):** no hay índice único en el repositorio; un doble envío podría duplicar valoraciones.
6. **Timeouts en RPC:** las RPC críticas no tienen límite de espera en el cliente; propuesta de límite uniforme con mensaje neutral.
7. **`cancelRideRequest`:** la llamada no envía `p_channel`; verificar si la RPC lo requiere.
8. **Expedición de conductor (`completed`):** el `catch` no distingue un error posterior a la transición; propuesta de releer el viaje antes de mostrar error.
9. **Caché cifrada:** las cachés de cuenta siguen en `SharedPreferences` sin cifrar; alternativa `flutter_secure_storage` (nueva dependencia, pendiente de aprobación).
10. **Flujo muerto de billetera en `express_account_pages`:** referencia antigua; revisar y retirar si no tiene llamadas.
11. **`connectivity_plus`:** no añadido. El detector actual usa solo lecturas reales, que es más fiable que el estado de la interfaz de red.

## 7. Riesgos residuales

- Estado `stuck` en `choosingPayment` sin límite de tiempo propio (solo el pre-chequeo tiene límite).
- Bloqueo de reintento de billetera vive solo en memoria: al cerrar y reabrir la app, el plan puede reintentarse; el servidor sigue siendo la barrera real (propuesta 1).
- Ventana corta de lectura de caché antes de terminar el cambio de cuenta en `signedIn` (§4).
- Sin pruebas en dispositivo ni en el navegador: las pruebas son unitarias, de widget y de contrato sobre el código fuente.

## 8. Restricciones respetadas

- Sin merge, sin despliegue, sin APK, sin cambios en `main`, #248 o #249.
- Sin cambios en ZEGO ni en flujos económicos del backend.
- Sin nuevas dependencias ni migraciones.
- `analysis_options.yaml` y `pubspec.lock` restaurados; no se confirmaron.
