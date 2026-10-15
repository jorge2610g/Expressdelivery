# ORDEN 011 — Cierre de revisión y preparación de pruebas

- Rama: `perf/map-continuity-offline-20261015` (PR #250, borrador contra `main`).
- Alcance: caché entre cuentas, continuidad del mapa, CI, limitación del cobro con billetera y procedimiento de prueba Android.
- No se fusiona, no se despliega, no se genera APK y no se toca Producción. No se modifica backend económico ni ZEGO.

## 1. Caché de otra cuenta en inicio, cambio de usuario y restauración de sesión

### Hallazgos de la auditoría

| Ruta | Riesgo antes de ORDEN 011 | Estado |
|---|---|---|
| Arranque móvil con sesión restaurada | El cambio de cuenta se hacía, pero no esperaba a las lecturas posteriores. | Corregido: cola ordenada (ver abajo). |
| Arranque web con sesión restaurada | No había cambio de cuenta al arrancar; solo en `signedIn`. | Corregido: `web_main.dart` cambia de cuenta antes de `runApp`. |
| Cierre de sesión seguido de inicio de otra cuenta | Borrado y cambio podían ejecutarse en paralelo; una lectura podía ver la caché de la cuenta anterior. | Corregido: operaciones encadenadas en `lib/core/account_device_cache.dart`. |
| Ubicación persistida (`express_last_valid_location_v1`) | Clave global del dispositivo, no ligada a `uid`. Leída al arrancar sin esperar al cambio de cuenta. | Corregido: `_readPersistedPosition` espera la cola. |
| Notificaciones procesadas (`express_processed_push_keys_v1`) | Clave global; solo deduplica, pero se leía sin esperar. | Corregido: `_claimPushMessage` espera la cola. |
| Caché de inicio y de aterrizaje del pasajero | Claves ligadas a `uid`; las lecturas podían ejecutarse antes del borrado. | Corregido: `_readCachedAccountBootstrap` y `_readCachedPassengerLanding` esperan la cola. |
| Memoria del proceso (posición, estado precargado, rutas, estado de conexión) | No se vaciaba al cambiar de cuenta. | Corregido: `lib/account_memory_reset.dart` (`forgetAccountMemory`). |

Diseño de la cola:

- `clearAccountDeviceCaches` y `switchAccountDeviceCachesIfNeeded` se encadenan en `_accountCacheQueue`.
- `awaitAccountDeviceCacheReady()` espera a la cola antes de cualquier lectura compartida.
- `switchAccountDeviceCachesIfNeeded` no hace nada si el `uid` es nulo o vacío, ni si coincide el marcador.
- Un fallo en una operación no bloquea las siguientes (`catchError` en la cadena).

### Pruebas

- `test/account_device_cache_test.dart`: 8 casos. Cierre de sesión, cuota y configuración conservadas, cambio de cuenta, misma cuenta, `uid` nulo, sin marcador, lectura durante el cambio espera y orden cierre→inicio.
- `test/orden011_contract_test.dart`: arranque web y móvil cambian de cuenta antes de `runApp`; cada lectura compartida espera a la cola; cierre y cambio pasan por la misma cola.

Residual: sin pruebas en dispositivo. El orden entre el evento `signedIn` y el primer render de la pantalla queda cubierto por la cola, pero no se ha medido en Android ni en navegador (ver §5).

## 2. Continuidad visual del mapa

Auditoría de solo lectura (subagente, flutter_map 8.3.2 revisado en el código fuente local) y verificación de cada punto contra el código.

| Escenario | Hallazgo | Estado | Acción |
|---|---|---|---|
| Zoom y desplazamiento | La capa no se reconstruye al mover la cámara; `keepBuffer 5`, `panBuffer 1`. | OK | Ninguna. |
| Cambio de tema claro/oscuro | La clave por tema desmontaba el mapa y dejaba un hueco hasta recargar teselas. | Riesgo | Corregido: sin clave por tema en `_expressMapTileLayer`. |
| Fallo de teselas (HTTP o sin red) | Errores silenciados a 1×1 transparente; un 1×1 no cuenta como tile real. | OK | Ninguna. |
| Capa saliente congelada | La congelación devolvía un proveedor vacío para toda petición: las teselas ya en caché de esa capa no aparecían al desplazarse. | Error | Corregido: `freeze()` cierra el cliente propio de esa capa; la caché sigue sirviendo. |
| Cambios rápidos de proveedor | Sin fugas ni generaciones obsoletas; la saliente se conserva. | OK | Pruebas existentes. |
| Atribución durante un relevo pendiente | Mostraba Mapbox mientras las teselas visibles eran OSM. | Riesgo | Corregido: la atribución sigue a la fuente en pantalla (`_outgoingMapbox ?? _activeMapbox`). |
| Cierre de capas y clientes | Cada cliente propio se cierra al liberar la capa; sin `setState` tras `dispose`. | OK | Ninguna. |
| Comentario obsoleto de «respaldo de 6 s» | No existe ningún temporizador. | Documental | Retirado. |

Riesgos residuales (no corregidos, documentados):

- **Arranque en frío con cuota de Mapbox y sin capa saliente:** el mapa puede quedar en blanco hasta que el disyuntor abre tras 8 fallos. Cambiarlo afecta a la cuota y a la lógica de conmutación; requiere decisión del propietario.
- **Token de Mapbox permanentemente inválido:** la capa saliente queda visible indefinidamente; el disyuntor reintenta cada ~2 min. Con la congelación corregida ya no bloquea teselas en caché.

Pruebas: `test/map_tile_handover_test.dart` (11) actualizado a la atribución que sigue a lo visible; `test/overlay_discrete_contract_test.dart` actualizado a `freeze()`; `test/orden011_contract_test.dart` cubre congelación, tema y atribución.

## 3. CI del último commit

- Commit `8a5d2c0b` (cambios de mapa de esta orden). Commit anterior `f78f629c` (caché de cuentas).
- Estado de CI en el momento de este informe: los jobs de `validate`, `change-inventory` y «Vercel Preview Comments» del commit anterior estaban en verde. El job «Express Single App - Web First QA» del commit `78e19d2a` había terminado en verde en el commit `c6fdd4f6` y en `7a546175`; para `78e19d2a` seguía en curso al consultarlo.
- El commit `8a5d2c0b` tenía sus jobs **en cola** (`queued`) al cerrar este informe. **Pendiente de confirmar**: no se afirma que pase hasta ver el resultado.
- Si algún job falla, se corregirá en la misma rama y se documentará aquí antes de cerrar la orden.

Validación local antes de subir:

- `flutter test --no-pub` (suite completa): **195 pruebas, todas en verde**.
- `flutter analyze --no-pub` en los archivos cambiados: **0 errores**. Quedan avisos de nivel info y warning que ya existían antes de esta orden en líneas no tocadas.
- `analysis_options.yaml` restaurado y sin cambios; no se confirman archivos generados.

## 4. Limitación documentada del cobro con billetera (sin cambios de backend)

No se modifica el backend económico ni se autorizan reintentos automáticos.

Estado actual:

- `pay_driver_subscription_with_country_wallet` (migración `20261012120500`) inserta una fila nueva de pago, debita la billetera y activa la suscripción en cada llamada. No tiene clave de idempotencia.
- En cliente, un resultado incierto (fallo de red, timeout o respuesta sin confirmación) bloquea el reintento del mismo plan **solo en memoria** hasta recargar la pantalla. El bloqueo no sobrevive a cerrar la app.
- Tras un resultado incierto, el cliente relee el estado de la suscripción; no reintenta el cobro.
- Pre-chequeo de billetera con límite de 15 s.

Limitaciones que siguen abiertas:

1. Si el servidor cobró y el cliente no recibió respuesta, el usuario puede ver «no sabemos si se completó» y el saldo ya descontado. Solo la relectura del servidor lo aclara.
2. Tras cerrar y reabrir la app, el bloqueo desaparece y el usuario podría volver a pulsar. La única barrera real sería una clave de idempotencia en servidor.
3. El reintento de un cobro duplicado no está prevenido en base de datos: propuesta documentada en el informe ORDEN 010 §6.1 (clave de idempotencia en `driver_subscription_payments`). Requiere migración y revisión económica; **no ejecutada**.

Decisión pendiente del propietario: autorizar o no la propuesta de idempotencia en servidor antes de considerar el cobro con billetera listo para producción.

## 5. Procedimiento de prueba en Android (sin generar APK)

Referencia de comparación: el video original que el propietario indicó. **No está en el repositorio ni se ha adjuntado en esta sesión**, por lo que no se ha podido comparar. El procedimiento queda preparado para cuando se facilite la ruta o el archivo.

Requisitos:

- Compilación de prueba de la aplicación oficial `com.express.usuario1` ya desplegada por el flujo habitual; no se genera APK nueva en esta orden.
- Cuenta de prueba (pasajero) y cuenta de prueba (conductor), ambas aisladas de datos de Producción.
- Dispositivo Android con datos móviles y Wi-Fi, y capacidad para activar modo avión.

Pasos (cada paso se graba en el mismo encuadre del video original y se anota la hora):

1. **Inicio en frío:** cerrar la app por completo, abrirla y registrar el tiempo hasta la primera pantalla útil. Comprobar que no aparecen datos de otra cuenta.
2. **Cambio de usuario:** cerrar sesión con cuenta A, entrar con cuenta B. Verificar que la ubicación, el estado y las tarjetas no muestran datos de A.
3. **Restauración de sesión:** con sesión iniciada, matar el proceso y reabrir. Verificar el tiempo hasta el primer render y que la caché corresponde a la cuenta activa.
4. **Seguimiento:** pedir un viaje de prueba. Verificar que el mapa no se vacía al cambiar de estado (asignación, llegada, inicio, fin).
5. **Mapa:** hacer zoom y desplazamiento; cambiar de tema claro/oscuro; comprobar que las teselas no desaparecen. Cambiar la fuente de teselas (si está disponible con la cuota) y verificar que la atribución coincide con lo visible.
6. **Pérdida de internet:** activar modo avión durante un viaje de prueba. Verificar el indicador «Sin conexión · datos hace X», que las acciones críticas aparecen bloqueadas y que el mapa anterior sigue visible.
7. **Reconexión:** desactivar modo avión. Verificar el paso a «Reconectando» y luego a en línea, y que el estado se relee desde el servidor.
8. **Comparación con el video original:** para cada paso, anotar si el comportamiento coincide, difiere o no se puede observar, con la hora del video.

Criterios de aceptación:

- Ningún dato de la cuenta anterior visible en ningún paso.
- El mapa no queda en blanco durante ningún cambio de estado ni de tema.
- Ninguna confirmación de viaje, pago o pedido sin respuesta del servidor.
- Los datos antiguos muestran su antigüedad.

Registro: cada prueba se anota con fecha, versión, cuenta usada (sin datos personales), resultado y captura o referencia de video. No se guardan credenciales en el informe.

## 6. Bloqueos y pendientes

- **CI del commit `8a5d2c0b`:** en cola al cerrar; pendiente de confirmar.
- **Video original de referencia:** no disponible en el repositorio ni en la sesión; el procedimiento de §5 no se puede comparar hasta recibirlo.
- **Idempotencia del cobro con billetera:** propuesta sin ejecutar; requiere decisión del propietario.
- **Pruebas en dispositivo:** pendientes; no se han ejecutado en Android ni en navegador.

## 7. Restricciones respetadas

- Sin fusión, sin despliegue, sin APK, sin cambios en Producción, `main`, #248 o #249.
- Sin cambios en ZEGO ni en el backend económico.
- Sin nuevas dependencias ni migraciones.
- Sin reintentos automáticos de cobro.
