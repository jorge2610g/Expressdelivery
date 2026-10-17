# ORDEN 009 — Continuidad visual del mapa, vista sin conexión y bloqueos seguros

- **Rama:** `perf/map-continuity-offline-20261015` (PR #250, borrador, contra `main` 95e22e27)
- **Restricciones respetadas:** `main`, Producción, Supabase, Google Play, PR #248 y PR #249 sin cambios; sin APK; sin despliegue; sistema ZEGO no tocado; sin migraciones; sin dependencias nuevas.
- **Decisión de diseño aplicada (autorizada para rama de prueba):** el mapa permanece visible durante asignación, cargas y cambios de estado. Los oscurecimientos de pantalla se sustituyen por indicadores discretos. Solo se bloquean acciones que no pueden ejecutarse con seguridad.

## 0. Límites de esta verificación

- **Sin dispositivo ni Android SDK.** Ninguna métrica de fotogramas, tiempo de inicio ni animación en teléfono. Las pruebas son unitarias, de widget y de contrato de fuente.
- **Sin video del propietario.** Las causas se derivan del código, no de fotogramas.
- **La interrupción de red se simula** mediante fallos inyectados (`http.ClientException`, `TimeoutException`), no con un corte real de radio.
- **Mapbox no se llama en pruebas.** Las pruebas de teselas usan imágenes sintéticas de 1x1 y 256x256 px.

## 1. Diagnóstico integrado (seis subagentes en ORDEN 008 y tres en ORDEN 009)

| Hallazgo | Evidencia (código de la rama) |
|---|---|
| El mapa era `flutter_map` con teselas raster, no el SDK de Mapbox GL. No hay recarga de estilo. | `pubspec.yaml`; ausencia de `MapWidget` y `setStyle` |
| La capa de teselas se retiraba a los 900 ms con `AnimatedSwitcher`, aunque las teselas nuevas no hubieran llegado. | `map_provider.dart` (antes de ORDEN 009, ~701-730) |
| Scrim de 32% a pantalla completa durante `select_ride_offer_v2`, sin timeout. | `video_style_home.dart` (`_ExpressTransitionOverlay`, antes de ORDEN 009) |
| Scrim de 45% con `AbsorbPointer` durante la espera de oferta del conductor. | `video_style_home.dart` (`_DriverOfferWaitingOverlay`, antes de ORDEN 009) |
| `connectivity_plus` no existe en el proyecto. Sin detección de sin conexión ni etiqueta de datos antiguos. | `pubspec.yaml`; búsqueda sin resultados |
| Los errores de red se propagan sin captura; la clasificación debe hacerse por tipo. | `express_service.dart` (llamadas sin `catch` de red) |
| La landing sin conexión inventaba cobertura y zona. Corregido en ORDEN 008. | `connected_shell.dart` (commit de ORDEN 008) |

## 2. Cambios implementados

### 2.1 Transición de mosaicos sin pérdida del mapa anterior
- **Nuevo `lib/map_tile_handover.dart`:**
  - `ExpressHandoverTileProvider`: `NetworkTileProvider` que puede congelarse. Una capa saliente deja de pedir teselas, pero conserva las ya visibles. Se usa `getImageWithCancelLoadingSupport`, que `flutter_map` llama por cada tesela.
  - `ExpressFirstRealTileImageProvider`: envuelve la imagen de cada tesela sin añadir peticiones y avisa una sola vez cuando llega una tesela real. Una tesela de 1x1 px es un fallo silenciado de `flutter_map` y no cuenta.
  - `TileHandoverController`: decide cuándo retirar la capa anterior. Se retira al llegar la primera tesela real de la nueva generación o tras 6 s de respaldo. Solo cuenta la generación actual (A→B→A dentro de la ventana no retira la capa equivocada). La atribución sigue a las teselas en pantalla.
- **`lib/map_provider.dart`:** `AnimatedSwitcher` sustituido por dos capas (saliente y entrante) gestionadas por el controlador. `ExpressMapProvider.attributionUsesMapbox` mantiene la atribución de Mapbox mientras sus teselas siguen visibles.
- **Cuota y licencias:** el envoltorio no añade peticiones (solo observa el flujo que `flutter_map` ya resuelve). Las capas salientes de Mapbox se congelan para no seguir consumiendo cuota. La atribución de Mapbox incluye el crédito de OpenStreetMap.

### 2.2 Indicadores discretos en lugar de oscurecimientos
- **`_ExpressTransitionOverlay`** (`video_style_home.dart`): ya no tiene velo de 32%. Es un indicador arriba, envuelto en `IgnorePointer`. Los textos y animaciones no cambian.
- **`_DriverOfferWaitingOverlay`:** velo de 45% y `AbsorbPointer` eliminados. La tarjeta de cuenta atrás va abajo y el mapa sigue usable.
- **Resumen de ganancias:** velo negro eliminado; se cierra tocando fuera, como antes.
- **Diálogos modales:** se conservan para decisiones de dinero o irreversibles (cobro de suscripción, confirmación de finalización, PIN de abordaje, motivo de cancelación, advertencia de zona de seguridad).

### 2.3 Vista sin conexión, recuperación automática y datos con antigüedad
- **Nuevo `lib/offline_status.dart`:** `ExpressConnectivityMonitor`, una máquina de estados sin dependencias nuevas.
  - `online → reconnecting` tras un fallo de red; `reconnecting → offline` tras tres fallos consecutivos; vuelve a `online` con cualquier lectura correcta.
  - Recuperación automática con espera creciente: 2, 4, 8, 16 y 30 s como máximo. Una sonda de solo lectura (`passengerActiveTripLiveState`) comprueba la conexión. Al volver a primer plano se sondea de inmediato.
  - `lastValidAt(fuente)` se fija solo tras una respuesta válida del servidor, nunca al leer caché ni al aplicar cambios optimistas.
  - Clasificación de errores: `TimeoutException`, `ClientException`, `SocketException`, `HandshakeException` y `AuthRetryableFetchException` son red. Los errores de datos del servidor no lo son.
- **Nuevo `lib/express_offline_banner.dart`:** indicador discreto arriba, sin velo y sin absorber toques. Muestra «Sin conexión · datos hace X» o «Reconectando · …». Si no hay datos guardados, dice «sin datos guardados». Nunca dice «en línea» sin conexión confirmada.
- **Integración en pantallas:**
  - Ambos mapas (pasajero y conductor) muestran el indicador como último hijo del `Stack`, para que quede encima del mapa.
  - Éxito y fallo de las recargas del pasajero (`_refreshHome`) y del conductor (`_refreshDriverHome`) alimentan la máquina de estados.
  - Al recuperar la conexión, cada pantalla hace una sola recarga (`_onConnectivityChanged`), sin duplicar lecturas.
  - La vuelta a primer plano llama a `onAppResumed()`.

### 2.4 Acciones críticas bloqueadas sin conexión (sin confirmar sin respuesta del servidor)
- Crear solicitud (`_createServiceBody`), seleccionar oferta (`_selectOffer`), avanzar viaje del conductor (`_advanceTrip`): guard `_expressOfflineBlocked(context)` al inicio. Muestra un aviso y no envía nada.
- Pago de suscripción con billetera (`driver_subscription_page.dart`, `_payWithWallet`): guard antes de `confirmingWallet`.
- Calificación (diálogo de calificación de `video_style_home.dart`): guard dentro del `onPressed`.
- Doble toque: `_confirmRoute` y `_createService` tienen banderas de vuelo (ORDEN 008). Las rutas comparten solicitudes en vuelo por clave (ORDEN 008).

## 3. Pruebas automatizadas

| Archivo | Verifica | Resultado |
|---|---|---|
| `test/offline_status_test.dart` (15) | Clasificación de errores; transiciones; tres fallos para offline; lastValidAt solo tras éxito; espera creciente 2-4-8-16-30 s; reprogramación; sonda exitosa y fallida; sonda con error de datos cuenta como en línea; vuelta a primer plano; etiqueta de antigüedad | 15/15 |
| `test/map_tile_handover_test.dart` (12) | Primera carga sin traspaso; traspaso a Mapbox hasta primera tesela real; atribución durante el cambio; generación antigua ignorada; A→B→A; respaldo por tiempo; mismo modo sin cambio; cancelación de temporizador; dispose; tesela 1x1 no cuenta; tesela 256 px cuenta una vez | 12/12 |
| `test/map_route_cache_test.dart` (3) | Peticiones concurrentes comparten una llamada de red; ruta fallida no se cachea; ruta exitosa sí | 3/3 |
| `test/express_offline_banner_test.dart` (5) | En línea no muestra nada; sin conexión muestra antigüedad; reconectando; no absorbe toques; la recuperación oculta el indicador | 5/5 |
| `test/overlay_discrete_contract_test.dart` (7) | Sin velos de pantalla completa; tarjeta de oferta sin `AbsorbPointer`; indicador de transición arriba sin absorber; banner en ambas pantallas; guards en tres acciones; sondas y registros en ambas pantallas; traspaso sin `AnimatedSwitcher` | 7/7 |
| `test/passenger_offline_and_guard_contract_test.dart` (3, ORDEN 008) | Sin landing fabricada; guards de doble toque; línea recta sin caché | 3/3 |
| Suite completa `flutter test --no-pub` | Regresiones en todas las pruebas | **175/175**, salida 0 |
| `flutter analyze --no-pub` sobre los archivos modificados | Errores de compilación | **0 errores**. Avisos e info preexistentes en líneas no modificadas |

**Prueba de sensibilidad:** la prueba de contrato del indicador de transición falla si se reintroduce `AnimatedSwitcher`, y la de sin velos falla si vuelve el color `0x52000000` o `0x73000000`.

**Supresión de lint documentada:** `ImageProvider.resolve` está marcado como no virtual en Flutter. El envoltorio lo sobrescribe a propósito y las pruebas de widget confirman que el despacho funciona. Se usa `// ignore: invalid_override_of_non_virtual_member` en dos lugares.

## 4. Riesgos residuales

1. **Sin dispositivo:** el comportamiento visual real del traspaso de teselas, del indicador y de la animación de la tarjeta de oferta no está verificado en teléfono.
2. **Detección por fallos, no por radio:** el estado sin conexión llega tras tres fallos (unos 6 s con la primera espera). Un corte total sin ninguna llamada en curso no se detecta hasta que una pantalla refresca o se vuelve a primer plano.
3. **Datos sin etiqueta fuera del indicador:** el indicador muestra antigüedad solo en estado sin conexión. Las tarjetas y listas con datos del último estado conocido no llevan etiqueta propia; falta una etiqueta por fuente de datos.
4. **Acciones no cubiertas por guard:** cancelar viaje (pasajero y conductor), cancelar solicitud, pedidos de Mercado (`marketplace_create_order`), suscripción por proveedor, y llamadas ZEGO. Estas acciones siguen dependiendo de respuesta del servidor, pero sin guard de conexión explícito.
5. **Doble toque entre dispositivos o pestañas:** las banderas son por instancia de pantalla. La protección completa requiere clave de idempotencia en servidor (ver §6).
6. **Caché de datos personales:** la fila de usuario, la última ubicación y la sesión siguen sin cifrar. El cifrado requiere una dependencia nueva de seguridad (ver §6).
7. **Tiempo de espera del RPC de oferta:** `select_ride_offer_v2` no tiene timeout en el cliente. Con el scrim retirado, el indicador queda visible mientras dura la llamada; falta un timeout con reconciliación.

## 5. Archivos modificados en esta orden

- `lib/map_tile_handover.dart` (nuevo): traspaso de teselas.
- `lib/offline_status.dart` (nuevo): máquina de estados de conexión.
- `lib/express_offline_banner.dart` (nuevo): indicador de conexión.
- `lib/map_provider.dart`: traspaso de capas, atribución, importación del módulo.
- `lib/video_style_home.dart`: scrims retirados, indicador de transición, guards, sondas, registros de éxito y fallo, banner en ambas pantallas, reconexión.
- `lib/driver_subscription_page.dart`: guard del pago con billetera.
- `test/map_tile_handover_test.dart`, `test/offline_status_test.dart`, `test/express_offline_banner_test.dart`, `test/overlay_discrete_contract_test.dart` (nuevos).
- `docs/reports/ORDEN_009_MAP_OFFLINE.md` (este informe).

## 6. Migraciones y dependencias (documentadas, no ejecutadas)

- **Migración de base de datos:** ninguna necesaria para estos cambios. La clave de idempotencia del cliente (`client_request_id`) sí la requiere para solicitudes, pagos, pedidos y calificaciones: tablas `ride_requests`, `driver_subscription_payments`, `marketplace_orders` y `ratings`, con restricciones únicas por usuario y `client_request_id`. **No ejecutada.**
- **Índice único de ofertas:** `driver_offers (ride_request_id, driver_id)` debe confirmarse en el esquema vivo mediante una consulta de solo lectura. **No ejecutada.**
- **Dependencia de seguridad nueva (`flutter_secure_storage`):** necesaria para cifrar la caché personal (fila de usuario, ubicación, sesión). **No añadida.**
- **Dependencia de conectividad (`connectivity_plus`):** no se añadió. La detección usa fallos reales de red, lo que evita una dependencia nueva.

## 7. Decisiones pendientes del propietario

1. Confirmar el tiempo del indicador de conexión y el texto «Sin conexión · datos hace X».
2. Autorizar la clave de idempotencia (migración) para solicitudes, pagos, pedidos y calificaciones.
3. Autorizar la dependencia `flutter_secure_storage` y el cifrado de la caché personal.
4. Autorizar la consulta de solo lectura al esquema vivo para verificar índices únicos.
5. Autorizar una sesión con dispositivo para medir fotogramas y tiempos antes y después (protocolo en ORDEN 008, §5).
6. Decidir si las cancelaciones y los pedidos de Mercado deben quedar bloqueados sin conexión (§4, punto 4).
