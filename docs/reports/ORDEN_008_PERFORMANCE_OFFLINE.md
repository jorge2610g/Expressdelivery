# ORDEN 008 — Rendimiento, continuidad del mapa y funcionamiento sin internet

- **Rama:** `perf/map-continuity-offline-20261015` (desde `origin/main` 95e22e27)
- **Respaldo:** `backup/performance-offline-20261015` (remoto, apunta a 95e22e27)
- **PR:** borrador, abierto contra `main` (no fusionado). Ver la respuesta de estado.
- **Estado:** cambios de código parciales y verificados por pruebas automatizadas; mediciones de dispositivo **no realizadas**; varias causas requieren decisión del propietario.
- **Restricciones respetadas:** sin cambios en Producción, Supabase, Google Play, `main`, PR #248 ni PR #249; sin APK; sin cambios en zonas, tarifas, pagos, suscripciones ni flujos de Taxi o Envíos.

## 0. Limitaciones de esta verificación

1. **El video del propietario no está en el entorno** (solo hay videos de ejemplo en la caché de pub). Los tiempos del video (00:01–00:07, 00:17–00:27, 00:54–01:11, 01:20–01:25) no se pudieron revisar fotograma a fotograma. Las causas se derivan del código.
2. **No hay dispositivos ni Android SDK.** No se midieron fotogramas, tiempos de inicio ni rebuilds en un teléfono. §6 define el protocolo y deja las métricas como pendientes.
3. **Corrección de premisa:** el mapa es `flutter_map` 8.3.2 con teselas raster, no el SDK de Mapbox GL. "Mapbox" significa la URL de teselas `api.mapbox.com`. No existe recarga de estilo (`setStyle`) en el código.

## 1. Diagnóstico (seis subagentes de solo lectura, integrados)

| Área | Hallazgo verificado en código (commit 95e22e27) | Referencia |
|---|---|---|
| **Mapa oscuro durante la asignación (~00:54–01:11)** | (a) Scrim negro de 32% a pantalla completa mientras `select_ride_offer_v2` está en curso, sin timeout. Duración = latencia del RPC. (b) En el lado conductor, scrim de 45% con `AbsorbPointer` mientras espera la oferta; se limpia solo al final de `_load`, después de varios `await` secuenciales. (c) `AnimatedSwitcher` de teselas que retira la capa anterior a los 900 ms **aunque las nuevas teselas no hayan cargado**. | `video_style_home.dart:307` y `:292-314` (`_ExpressTransitionOverlay`); `:10342-10375`; `map_provider.dart` ~672-701 |
| **Selección de ruta (~00:17–00:27)** | Ruta secuencial: Mapbox con 4 s, luego OSRM con 4 s. Caché en memoria de 3 min que **también guardaba la línea recta de respaldo**. Sin deduplicación de peticiones en vuelo. `_fitRoute` sin guarda de reentrada. `_confirmRoute` solo consultaba `routing`, que se activa después de dos `await`. | `map_provider.dart` 438-465 (antes); `video_style_home.dart:2826`, `:2900` |
| **Final del viaje (~01:20–01:25)** | Conductor: dos RPC en serie antes de cambiar la UI. Pasajero: sin finalización optimista; la UI cambia cuando el sondeo de 3 s devuelve nulo. | `video_style_home.dart:8515-8580`, `:1819-1820` |
| **Rebuilds** | Sondeo del pasajero cada 3 s reemplaza `homeFuture` y reconstruye la página completa al cambiar la posición del conductor. `build()` del pasajero llama efectos secundarios (`_refreshPassengerActiveRoadRoute`). Sin `RepaintBoundary` en los mapas. | `video_style_home.dart:1231`, `:1841-1868`, `:5013`, `:5176`, `:10042` |
| **Animaciones y efectos** | No hay `BackdropFilter` ni `ImageFilter` sobre el mapa. Sombras grandes en tarjetas. Radar de búsqueda y marcadores de vehículos con `repeat()` sin límite. | `video_style_home.dart:16611`, `:16784`, sombras en `:326` y siguientes |
| **Inicio** | Cadena secuencial: `Supabase.initialize` → puerta de acceso → permisos → `_bootstrap` → `myUser` (duplicado) → cuota (duplicada) → `preloadPassengerHomeState` → `_load` (`myUser` otra vez). Dos llamadas idénticas. `syncForSession` de voz arranca en el primer frame. Splash fijo de 1550 ms y 1350 ms (diseño, no tocado). | `mobile_main.dart:81`, `:141`; `connected_shell.dart:285-333`; `connected_experience.dart:430` |
| **Sin internet** | Sin `connectivity_plus` ni detección de conectividad. Sin etiqueta de "datos anteriores". **`_offlinePassengerLanding` fabricaba** `inside_coverage: true`, zona "Express" y "Usando tu última ubicación guardada" sin que exista ubicación guardada. | `connected_shell.dart:137-158` (antes) |
| **Caché de datos personales** | Fila completa de `users` en SharedPreferences sin cifrar; última ubicación válida sin cifrar (hasta 30 días); landing con latitud y longitud; sesión de autenticación en SharedPreferences (inferido). | `connected_shell.dart:44-55`, `:79-150`; `location_service.dart:16`, `:50-52`; `express_supabase_bootstrap.dart:18-40` |
| **Idempotencia** | Idempotentes: cancelación de solicitud y de viaje, `advance_trip`, `start_trip_with_pin`, `select_ride_offer`, recargas de billetera, suscripción con pago pendiente. **No idempotentes:** creación de solicitud (`createRideRequest`, insert sin clave única), creación de envío, `marketplace_create_order`, pago de suscripción con billetera, `submitRating` (depende de índice que no está en el repo). | `express_service.dart:959-1141`, `:1434`, `:106-125`, `:1596`; migraciones 026, 034, 093 |

**Causa dominante del mapa oscuro:** la combinación de scrim durante RPC sin timeout y de la retirada prematura de la capa de teselas. No es un fallo exclusivo del SDK.

## 2. Cambios implementados

### 2.1 Sin datos fabricados sin conexión (requisito 3)
- **`lib/connected_shell.dart`:** se elimina `_offlinePassengerLanding()`. Sin ubicación ni caché válida, `_preparePassengerLanding` devuelve `null`, y `initialPassengerLanding` queda en `null`. El pasajero entonces resuelve su propio estado (ubicación requerida o zona no disponible, `_passengerLandingUnavailable`), que ya existe en `connected_experience.dart:800-830`.
- Efecto: sin conexión y sin caché, la app ya no afirma cobertura ni zona.

### 2.2 Rutas: sin caché de la línea recta, sin peticiones duplicadas
- **`lib/map_provider.dart`:**
  - `drivingRoute` deduplica peticiones en vuelo por clave (`_routeInFlight`). Dos peticiones idénticas comparten una sola llamada de red.
  - La línea recta de respaldo (`provider: 'direct'`) **ya no se cachea**. Antes podía ocultar una ruta real durante 3 minutos.
  - Se añade `routeHttpClient` (`@visibleForTesting`) para que las pruebas sustituyan HTTP. En producción es el cliente por defecto.
- Sin cambios en el tiempo de vida de la caché (3 min) ni en los tiempos de espera (4 s).

### 2.3 Doble toque en confirmar o crear solicitud
- **`lib/video_style_home.dart`:** `_confirmRoute` y `_createService` pasan a ser envoltorios con bandera `_confirmRouteInFlight` / `_createServiceInFlight` (con `try/finally`). El cuerpo original se conserva en `_confirmRouteBody` y `_createServiceBody`, sin cambios de lógica.
- Efecto: un segundo toque durante las consultas de cobertura o la publicación no inicia un segundo flujo.

## 3. Lo que no se implementó (requiere decisión o validación)

| Propuesta | Por qué no | Decisión necesaria |
|---|---|---|
| Quitar o cambiar el scrim de 32% durante `select_ride_offer_v2` (`video_style_home.dart:307`) | Cambia el diseño visible; el scrim cubre el tiempo del RPC | **Propietario:** ¿banner no bloqueante o scrim más corto? |
| Quitar el scrim de 45% de espera de oferta del conductor (`:10375`) | Cambia el diseño y permite tocar controles obsoletos | **Propietario** |
| Dejar de retirar la capa anterior de teselas a los 900 ms (`map_provider.dart` ~672) | Cambia cuándo se usa Mapbox y el consumo de la cuota | **Propietario** (presupuesto Mapbox) |
| Finalización optimista del viaje (pasajero y conductor) | Muestra "completado" antes de confirmación del servidor | **Propietario** |
| Mover el sondeo de 3 s a un `ValueNotifier` para la posición del conductor | Riesgo medio: el marcador debe seguir al GPS; requiere prueba en dispositivo | Aprobación técnica tras medir |
| Diferir `syncForSession` de voz fuera del primer frame | **Riesgo medio para Taxi:** invitaciones de llamada podrían llegar tarde en un arranque en frío | **Propietario** + QA de llamadas |
| Cambiar el splash de 1550 ms y 1350 ms | Tiempo visible de diseño | **Propietario** |
| `RepaintBoundary` alrededor de `FlutterMap` (`:5176`, `:10042`) | Efecto visual nulo, pero no se midió ganancia; sin dispositivo no se valida | Aprobación técnica tras medir |
| Cifrar o retirar caché personal (fila de usuario, ubicación, sesión) | Requiere dependencia nueva (`flutter_secure_storage`) y migración de datos locales | **Propietario** (dependencia nueva) |
| Clave de idempotencia del cliente (`client_request_id`) en solicitudes, pagos, pedidos y calificaciones | Requiere migración y cambios en funciones; fuera de alcance | **Propietario** (migración) |
| Índice único verificado en `driver_offers (ride_request_id, driver_id)` | Tablas centrales no están en `supabase/migrations`; hay que consultar el esquema vivo en solo lectura | **Propietario** |
| `connectivity_plus` para detectar sin conexión y mostrar etiqueta de datos anteriores | Dependencia nueva; la etiqueta requiere diseño | **Propietario** |

## 4. Pruebas automatizadas

| Archivo | Qué verifica | Resultado |
|---|---|---|
| `test/map_route_cache_test.dart` (3 pruebas) | Peticiones concurrentes comparten una llamada de red; una ruta fallida devuelve línea recta **no cacheada** y la siguiente llega a la red; una ruta exitosa se cachea | 3/3 pasan |
| `test/passenger_offline_and_guard_contract_test.dart` (3 pruebas) | Contrato de fuente: no hay datos fabricados sin conexión; los envoltorios de doble toque existen; la línea recta no se escribe en caché | 3/3 pasan |
| Suite completa `flutter test --no-pub` | Regresiones en las 45 pruebas existentes | **136/136 pasan**, salida 0 |
| `flutter analyze --no-pub` sobre los tres archivos | Errores de compilación | **0 errores**. 146 avisos e info, todos preexistentes en líneas no modificadas |

**Verificación de sensibilidad:** la prueba de caché falla con el código anterior, porque la línea recta se cacheaba durante 3 minutos. Las pruebas de contrato fallan si se reintroduce `_offlinePassengerLanding` o se quitan los envoltorios.

**Nota sobre el entorno:** se usó Flutter 3.47.5 (`/home/user/flutter/bin/flutter`) con `--no-pub`. El análisis y las pruebas modifican `analysis_options.yaml` y crean `pubspec.lock`; ambos se restauraron antes del commit.

## 5. Métricas (antes y después)

**No medidas.** Motivos: no hay dispositivo, no hay Android SDK y el video no está disponible. Los datos siguientes son el punto de partida conocido, no mediciones:

| Métrica | Antes | Después | Estado |
|---|---|---|---|
| Tiempo al primer frame (Android, perfil) | — | — | No medido |
| Tiempo hasta mapa interactivo | — | — | No medido |
| Peticiones de red al inicio (duplicadas) | 2 `users.select`, 2 `mapbox_quota_state` | sin cambios | Contado en código; cambio pendiente de decisión |
| Peticiones de ruta por toque | hasta 2 (Mapbox y OSRM), sin deduplicar | 1 por clave en vuelo | Verificado por prueba |
| Solicitudes de viaje por doble toque | posible 2 | 1 | Verificado por lógica; no probado en dispositivo |
| Fotogramas durante la transición | — | — | No medido |

**Protocolo sugerido** (para la siguiente sesión con dispositivo): `flutter run --profile --trace-startup` para el inicio; DevTools Timeline para fotogramas en la transición de asignación; conteo de reconstrucciones con un contador de prueba en el widget del mapa; 10 repeticiones por escenario, con p50, p95 y máximo, en un CSV `docs/reports/perf/home_map_<fecha>_<antes|después>.csv`.

## 6. Riesgos residuales

- Las causas de mapa oscuro de §1 siguen presentes hasta que se decidan los cambios de §3.
- Sin conexión y sin caché, el pasajero verá el estado "ubicación requerida" o "zona no disponible" en lugar de una pantalla vacía. Hay que confirmarlo en dispositivo.
- La deduplicación de rutas es en memoria: no sobrevive a reinicios de la app.
- La guarda de doble toque es por instancia de pantalla; no protege contra dos pestañas o dos dispositivos. Eso requiere la clave de idempotencia de §3.
- La caché de datos personales no cambió: sigue sin cifrar.

## 7. Archivos modificados

- `lib/connected_shell.dart`: eliminación de la landing fabricada; el tipo de retorno pasa a anulable.
- `lib/map_provider.dart`: deduplicación en vuelo, sin caché de línea recta, cliente HTTP inyectable.
- `lib/video_style_home.dart`: envoltorios de doble toque para `_confirmRoute` y `_createService`.
- `test/map_route_cache_test.dart` (nuevo).
- `test/passenger_offline_and_guard_contract_test.dart` (nuevo).
- `docs/reports/ORDEN_008_PERFORMANCE_OFFLINE.md` (este informe).

## 8. Decisiones para el propietario

1. ¿Autorizar cambios de diseño para el scrim de asignación (§3, tres primeras filas)?
2. ¿Autorizar la finalización optimista del viaje, con confirmación del servidor y reversión en error?
3. ¿Autorizar la dependencia `flutter_secure_storage` para cifrar caché personal?
4. ¿Autorizar una migración con `client_request_id` para solicitudes, pagos, pedidos y calificaciones?
5. ¿Autorizar consulta de solo lectura al esquema vivo para verificar índices únicos?
6. ¿Aprobar la sesión con dispositivo para medir §5?
