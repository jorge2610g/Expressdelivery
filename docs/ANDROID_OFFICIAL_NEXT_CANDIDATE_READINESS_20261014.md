# QA histórico — decisiones de Delivery actualizadas el 2026-10-24

Las observaciones de este documento son del candidato Android del 2026-10-14. Los repartidores comerciales usan ahora Express Principal, y los comercios usan Express Restaurante. Ver `EXPRESS_DELIVERY_PRODUCT_DECISIONS_20261024.md`.

# Express — consolidación para la próxima APK oficial
**Corte:** 14 de octubre de 2026. **No equivale a APK compilada/publicada.**

## Regla de entrega
Solo una aplicación Android `com.express.usuario1` (pasajero Taxi, Envíos, compras Delivery; conductor Taxi y Envíos) y una web en `https://expressviajes.online/`. El runtime Preview/Producción lo asigna Supabase por cuenta. **No volver a crear paquetes APK Preview separados.**

## Integraciones confirmadas en `main` para el próximo candidato
| Módulo | Integración | Qué falta comprobar en dispositivo |
| --- | --- | --- |
| Retrato privado estable del conductor y refresco del perfil | PR #241 → `036459795f9860bdf28ac1fe4de73996709ad9e9` | Foto nueva, caché, perfil de pasajero/conductor, app reinstalada |
| Historial del conductor: Envíos personales antiguos | PR #238 → `e175bb78e798078d60c0a0e9c0d8ede1b45f17f9` | Taxi, paquetería actual/legacy, no mostrar Marketplace |
| ZEGO Android: reinicio de señalización al volver a primer plano | PR #240 → `ce8a0ef5a77fcf0930b3756184976bb141976832` | Dos teléfonos, ZIM, FCM, llamadas abiertas/cerradas/segundo plano |
| Cuatro filtros Actividad en una fila | PR #157 → `30a9efff53cf5e8bd1969fb6a66752c8d550863d` | Pantallas Android pequeñas y grandes |
| Delivery: Mis cupones, Plus, etiquetas Restaurantes | PR #234 → `c450c8e7ef9aa70d119bffa03c992b7b9d4a8f44` | Cupones por cuenta/canal/zona, checkout y suscripción Plus; no activar Delivery real |
| Permiso nativo de micrófono y solicitud antes de llamadas | `16f22b394877483d3dd0c8dccad24611fad17744` + `2c919149bfcc692a7b23598e9d8b82582f8341fb` | Android muestra permiso, publica/captura voz, altavoz, silencios/cancelación |
| Retirada de segundo paquete y web Preview | commits previos de 14/10 y Supabase build-worker v39/push-dispatch v40 | QA interno conserva su cuenta/canal sin romper autenticación ni FCM oficial |

## Consolidación posterior para la APK única — 14/10/2026

| Módulo | Cambio integrado a main | Validación pendiente |
| --- | --- | --- |
| Acceso a trabajar como conductor | `7832ac8208d96867d36343806bb74b4a85fcfc4e`: el cliente consulta `driver_subscription_allows_dispatch` con su propio usuario, igual que el servidor; rechaza respuesta inválida o fallo y no confunde plan vencido con permiso por zona | QA de conexión en Iquique y zona donde el plan sí es obligatorio |
| Corrección de documentos desde notificación | `8c63b8d3103b4736752f27160c03fb1bb3baba9c`: abre directamente documentos editables del conductor sin intentar cambiar a un modo no aprobado; añade test contractual | Validar notificación real; la revisión individual de fotos por Admin sigue requiriendo migración/UI propias |

**Copia de seguridad**: rama `backup/pre-android-candidate-consolidation-20261014` conservada desde `e393ddc869b4b97983d0ac570011db05643ed36b`.
Los PR #228, #160, #196, #161 y #224 quedaron **cerrados como obsoletos** con comentarios, NO borrados del historial. No volver a fusionarlos.

**Criterios de liberación todavía abiertos:**
1. Audio bidireccional ZEGO Android y Web↔Android en dos teléfonos, permisos de micrófono y altavoz.
2. Push de llamadas en segundo plano: ZEGO Console FCM Data Messages + Resource ID en el Edge backend y test con app cerrada; el registro previo mostró `resource_id_configured=false`.
3. Conexión/recepción de ofertas del conductor, límites de zona/canal, Taxi y Envíos end-to-end.
4. Fotos autorizadas nuevas, permisos RLS y actualización visible en ambos roles.
5. Revisión por foto de documentos mediante Admin: PR #155 depende de RPC y panel; no ejecutar migración sin revisión de seguridad.
6. PR #150 optimización de refrescos: rebasar sin reemplazar `video_style_home.dart` actual, medir llamadas y latencia en QA.
7. Tarifas dinámicas #222 y premios automáticos #190: requieren criterios de producto y verificación financiera, NO aplicarlos por inercia.
8. Flutter/CI Web puede dar verde sin compilar un nuevo Android nativo; para probar el permiso de micrófono es necesaria la próxima **única APK oficial**, solo por pedido explícito. Google Play requiere aprobación distinta.

## Actualización final de código compartido — 14/10/2026

**QA conjunto verificado:** GitHub Actions run [`38655740706`](https://github.com/jorge2610g/Expressdelivery/actions/runs/38655740706), `main` funcional `ffd4261213e9f0b2906bd20720504c1212280081`: **127 pruebas Flutter aprobadas**, análisis `lib/` correcto, compilación Web principal y portal comercial correcta. **No se ejecutó build Android ni QA física; no declarar APK lista para publicación sin gates de micrófono/ZEGO/push/GPS.**


- **Web: llamadas de voz con interfaz de teléfono:** PR #242 fusionada en `main`, commit `05bf3237d89938957f64ba217f398a9aadef9e14`. Port del candidato #236 a la base vigente; no toca llamada nativa Android. Simulación Node, análisis Flutter y compilaciones Web superaron CI. PRs #236 y #233 se archivaron como alternativas obsoletas. Llamadas Web↔Android y controles en Chrome físico aún por certificar.
- **Conductor: filtrar eventos de otra zona/canal antes de refrescar:** PR #243 fusionada en `main`, commit `ffd4261213e9f0b2906bd20720504c1212280081`. Tres callbacks de Realtime (ride_requests, delivery_requests, zone_service_catalog) descartan cambios explícitamente ajenos al contexto y mantienen compatibilidad con eventos legacy sin metadatos. Pruebas de contrato y Flutter/Web CI aprobadas. **No sustituye** el filtrado por zona en el servidor ni el throttle previstos en PR #150; sigue pendiente medir consultas y latencia de ofertas en QA.
- Se mantiene un solo paquete Android, `com.express.usuario1`. **No se generó una APK ni AAB** con estos cambios. Las pruebas automáticas de Flutter/Web no prueban llamadas Android, Bluetooth, push/background, sonido bilateral, velocidad de ofertas ni cobros reales.

## Integración de documentos adicionales cerrada en código (15/10/2026)

- **Adminexpress `main`:** PR #98, commit `6541fdf3daeb40d57bcd42dd04a5780929df7a52`, seguido de `76f692e585e227f1e588c448089ba41a7d5a0482`: revisión por foto de documentos genéricos, también si solo se requiere reverso o selfie; controles por estado y versión.
- **Expressdelivery `main`:** PR #244, commit `836a489bc46207df730ce03cf5128d2f5d10ebbe`: migración versionada `20261015000500_generic_driver_document_photo_review_v2.sql` con comprobación de administrador/entorno, rutas/versiones de imágenes, protección contra aprobación falsificada, y exclusión de identidad/licencia y activación automática del conductor. PR anterior #155 archivado para no aplicar trigger obsoleto.
- QA código PR #244: [CI](https://github.com/jorge2610g/Expressdelivery/actions/runs/38657573625), **128 pruebas aprobadas**, `flutter analyze lib` y dos Web builds. El código migrado no fue ejecutado en Supabase Production.
- **Activación pendiente intencionadamente:** no hay entorno de base de datos QA en la conexión actual (solo proyecto Supabase `zgpijrznvaskgcmauwxx`). Aplicar SQL a ese proyecto sin RLS/funciones probadas por usuarios autenticados puede afectar verificaciones de conductores; requiere QA de aprobación/rechazo de foto, rechazo visible al conductor y confirmación de entorno correcto. La web Admin también tiene publicación protegida, separada del commit. Esto NO bloquea compilar APK para Taxi pero sí impide certificar revisión por foto.

## Bloqueantes externos verificables previos a certificar llamadas Android

- ZEGOCLOUD: el backend `zego-call` usa `ZEGO_RESOURCE_ID` desde configuración privada. Consulta 48 h en `private_voice_calls`: **41 intentos, 0 contestados y 0 con Resource ID** (14/10/2026, consulta agregada). Requiere crear/validar recurso push ZEGOCLOUD, asociar FCM Data Messages Android y configurar `ZEGO_RESOURCE_ID` en secretos Supabase. No inventar Resource ID ni exponer secretos en GitHub.
- Android: una sola APK oficial `com.express.usuario1` (no creada en esta sesión) y prueba con dos teléfonos: voz ambos sentidos, llamada entrante con pantalla apagada/app cerrada, micrófono, altavoz, zonas, push, GPS, oferta Taxi y Envíos, historial/documentos/imagen actual.
- Funciones financieras WIP PR #222 (multiplicadores demanda) y #190 (premios a saldo): ningún cobro/premio automático se activó; sin máximo y reglas de aprobación no deben lanzarse con la APK. Mantener apagadas en el candidato y tratar aprobación financiera separada.
- Optimización backend PR #150: el filtro de eventos de otras zonas/canales (#243) **sí** está en main; los cambios de filtro del servidor/throttle de PR #150 no están certificados, necesitan medición de ofertas ≤2 s y conteo real de RPC en QA. Evitar desplazar ofertas con una fusión obsoleta.

## Funcionalidad existente en main, NO certificada en físico ni necesariamente activa comercialmente
Taxi y Envíos (solicitud, aceptación, GPS, ofertas, tarifas, zonas), registro/conductor/documentos/Didit, suscripciones y billetera, campeonatos y estadísticas, Delivery V2 de cliente (catálogo/carrito/checkout/seguimiento), cupones, notificaciones y enlaces para compartir viaje.

Compilación Web y tests automatizados **no equivalen a** prueba Android con micrófono/GPS/FCM de dos dispositivos. El APK/AAB firmado candidato anterior `1.6.1+140` es de un SHA anterior y **no** contiene estas integraciones; no atribuirle estos arreglos.

## Trabajo que NO está listo para fusionar indiscriminadamente
- PR #228: alternativa de foto potencialmente solapada por #241; no mezclar caches.
- PR #233/#236: alternativas de interfaz telefónica Web; requieren escoger una y probar voz/controles Web ↔ Android sin afectar Taxi.
- PR #155: revisión manual de documentos por foto, falta emparejar UI Admin/DB, despliegue RLS y QA.
- PR #150: optimización fuerte del refresco conductor, diff obsoleto/conflictivo con `video_style_home.dart` de `main`; rebasar por fases y medir latencia/ofertas.
- PR #199: selección de módulos por zona, cambio antiguo de RPC; comparar con migraciones actuales antes de reemplazar funciones del backend.
- PR #202: vuelve a ofrecer delivery comercial al conductor de Express principal; contradice la separación de Repartidor, **no integrar como está**.
- PR #222: escalones de demanda 0,5, falta decidir límite y cotización real server-side, no modificar producción.
- PR #190: créditos automáticos de campeonatos, no desplegar SQL que mueva fondos sin revisión financiera/autorización.
- PR #172: suite de conductor antiguo sin QA final; varios recorridos ya existen mediante implementaciones posteriores.
- Express_Repartidor y Express_Restaurante: backends/apps independientes pendientes de completar. No retirar los consumidores legacy hasta transición integral.
- APK oficial siguiente: solo por pedido expreso del propietario, jamás activar Play Store al integrar `main`.

## Checklist previo a APK única
1. `python3 .github/scripts/check_single_app_contract.py`; `flutter analyze lib`; `flutter test`; Flutter Web release.
2. Verificar Supabase/RLS y tokens FCM/ZEGO de un solo paquete.
3. Hacer QA con cuentas Preview en la misma Web real para tarifas, ciudades y pantallas compartidas.
4. Autorizar generación de **un** APK/AAB oficial si los componentes nativos no pueden probarse en Web.
5. Probar Taxi y Envíos bidireccional, micrófono, audio, segundo plano, GPS, documentos, historia y foto en dispositivos físicos.
6. Solo luego aprobar/promover el candidato con hashes. Publicación Google Play requiere autorización separada.
