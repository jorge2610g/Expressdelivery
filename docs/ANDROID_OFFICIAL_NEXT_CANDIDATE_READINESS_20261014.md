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
