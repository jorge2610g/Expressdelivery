# Documento histórico — decisión sustituida el 2026-10-24

El propietario confirmó que los repartidores comerciales usarán la app Express Principal con el mismo flujo y pantallas. No crear Express_Repartidor. El estado vigente está en [`EXPRESS_DELIVERY_PRODUCT_DECISIONS_20261024.md`](EXPRESS_DELIVERY_PRODUCT_DECISIONS_20261024.md). El resto de este documento conserva la decisión anterior como registro histórico.

# Express — Separar únicamente el reparto de pedidos comerciales (2026-10-14)

## Decisión corregida del propietario

La aplicación principal **NO** se divide ni pierde las compras a restaurantes.
Conserva cinco recorridos:

1. Cliente: Taxi.
2. Cliente: Envíos/paquetes.
3. Cliente: Delivery/compra en restaurantes, supermercados y tiendas.
4. Conductor: Taxi.
5. Conductor: Envíos/paquetes.

Solo se retiran las **ofertas nuevas de reparto de pedidos de restaurantes/tiendas** del modo conductor de la aplicación principal; esas entregas corresponderán a `jorge2610g/Express_Repartidor`.

El pedido del cliente y la gestión del comercio siguen conectados al mismo backend Supabase y al canal de identidad Preview/Producción que les corresponda. El portal de comercios puede migrarse separadamente a `jorge2610g/Express_Restaurante`.

## Estado REAL del primer cambio seguro — PR #235 fusionada, apps nuevas pendientes

**Actualización 2026-10-14:** PR #235 fusionada en `main` (merge `61a83ae290a94c456d1a53728ed1ff34198975b3`). El filtro está en `lib/core/driver_work_scope.dart` y en el flujo de nuevas ofertas de `lib/video_style_home.dart`. Compilación Android candidata `1.6.1+140` desde este SHA: APK/AAB firmados, QA físico pendiente. **No significa que Express_Repartidor exista funcionalmente ni que las push comerciales se hayan separado.** Consultar `docs/EXPRESS_CODE_AUDIT_AND_FOUR_APP_PLAN_20261014.md`.

## Alcance del primer cambio seguro (YA fusionado en el código; no asegura release validado)

- Filtrar los permisos visibles/solicitables del conductor principal a `ride` y `parcel`.
- Excluir cualquier solicitud de `delivery_requests` que tenga `marketplace_order_id` al generar nuevas ofertas o ventanas emergentes.
- Mantener el soporte de lectura/seguimiento de entregas ya asignadas, para no abandonar servicios activos preexistentes.
- **No** cambiar pantallas, carrito, pagos, pedidos ni seguimiento del cliente para Marketplace.
- **No** borrar funciones RPC, tablas ni migraciones del backend compartido.
- **No** modificar autorizaciones de usuarios, flags comerciales, tarifas, zonas, claves, despliegues ni APK/Play Store.
- Esta rama no implementa por sí sola la app nueva de Repartidor ni garantiza que las push antiguas de Marketplace estén separadas por aplicación. La segregación de tokens FCM, push, asignación del backend y pruebas E2E es una fase distinta **antes de lanzar Express_Repartidor**.

## Validación pendiente

- QA automatizada: funciones de filtrado para `ride`, `parcel` y `market`; pruebas Flutter; compilación Web en CI.
- QA con cuentas Preview: mismo mapa y ofertas de Taxi/Envíos; cliente navega y compra en restaurante; modo conductor principal no ofrece repartos comerciales nuevos; pedidos de entrega ya activos siguen completables.
- Verificar notificaciones push por rol/aplicación y permisos de servidor antes de desplegar la nueva aplicación.
- El cambio ya fue fusionado por autorización del propietario; **no activar despliegue comercial hacia una app nueva inexistente**. Primero certificar en teléfono y migrar backend/push manteniendo pedidos anteriores.
