# Express Delivery V2 — Implementación multi-zona / multi-país

Fecha de implementación candidata: 2026-10-03 / 2026-10-04 (America/Santiago)

> Estado: **candidato de desarrollo**.
>
> Las migraciones 085–088 están versionadas y probadas con ROLLBACK, pero
> **NO deben aplicarse al backend compartido ni publicarse a Preview sin
> autorización explícita**.
>
> Producción de Marketplace debe permanecer OFF hasta aprobación posterior.

## 1. Objetivo

Express Delivery V2 consolida los flujos observados en las referencias de
PedidosYa y los requisitos propios de Express en un solo módulo:

**Inicio → categoría → comercios/productos → comercio → menú → producto con
opciones → carrito → último paso → pago → seguimiento → PIN de entrega →
reseña.**

La implementación conserva la regla arquitectónica de Express:

- identidad de usuario global;
- contexto financiero/operativo separado por país;
- moneda por país/zona;
- reglas comerciales y disponibilidad por zona;
- suscripciones/reglas regionales sin reinterpretar dinero de otro país.

## 2. Respaldo previo

Antes de crear V2 se congelaron ramas de respaldo:

- App: `backup/pre-express-delivery-v2-2026-10-03`
  - SHA base: `9f506b027a320d18e0d6d0a22c97db1588f862ae`
- AdminExpress: `backup/pre-express-delivery-v2-2026-10-03`
  - SHA base: `5443da47f4d046898009344ffb040376cbc5685a`

Ver snapshot detallado:
`docs/backups/EXPRESS_DELIVERY_V2_PRECHANGE_2026-10-03.md`.

## 3. Reglas multi-país y multi-zona

### País

El `country_code` es dato explícito.

- Chile: `CL`, moneda operativa actual `CLP`.
- Bolivia: `BO`, moneda operativa actual `BOB`.

Pedidos, notificaciones Delivery, facturación, recomendaciones y direcciones
se consultan con el contexto de país activo.

Cambiar de país no convierte ni reutiliza montos de otra moneda.

### Zona

Los comercios, tarifas, disponibilidad, cupones y campañas pueden limitarse
por `zone_id`.

Ejemplos actuales:

- Iquique → CL / CLP.
- Trinidad → BO / BOB.

Al cambiar de zona, el Home vuelve a cargar contenido de esa zona. Si cambia
de zona con un carrito activo, el carrito se limpia para impedir pedidos
mezclados entre comercios/contextos incompatibles.

## 4. Migraciones V2

### 085 — schema

`supabase/migrations/085_express_delivery_v2_schema.sql`

Agrega:

- país/zona/default/instrucciones a direcciones guardadas;
- horario, apertura manual, pedido mínimo, patrocinado y tags a comercios;
- ámbito zona/país en banners;
- secciones internas de menú;
- promoción y precio comparativo por producto;
- rating/reviews/sold_count/tags/producto destacado/patrocinado;
- grupos de modificadores y opciones;
- venta cruzada;
- reseñas verificadas;
- secciones dinámicas de Home;
- cupones + redenciones;
- perfiles de facturación por país;
- snapshot de modificadores/notas/promos en order items;
- país, dirección, instrucciones, cupón, facturación, donación y hashes PIN
  en orders;
- índices;
- trigger para fijar país del pedido desde la zona.

Las nuevas tablas RPC-only tienen RLS activado y permisos explícitos.
El perfil de facturación usa políticas own-user.

### 086 — customer APIs

`supabase/migrations/086_express_delivery_v2_customer_functions.sql`

RPC principales:

- `marketplace_available_zones`
- `marketplace_saved_addresses_v2`
- `marketplace_add_saved_address_v2`
- `marketplace_home_v2`
- `marketplace_category_feed_v2`
- `marketplace_merchant_detail_v2`
- `marketplace_product_detail_v2`
- `marketplace_validate_coupon`
- `marketplace_quote_order_v2`
- `marketplace_create_order_v2`
- `marketplace_delivery_notifications` (legado V2 inicial)
- `marketplace_mark_notification_read`
- `marketplace_upsert_billing_profile`
- `marketplace_issue_order_code`
- `marketplace_verify_order_code`
- `marketplace_submit_review`

El PIN usa bytes aleatorios de `extensions.pgcrypto`, guarda solo SHA-256
y nunca persiste el código en texto plano.

### 087 — admin APIs

`supabase/migrations/087_express_delivery_v2_admin_functions.sql`

Configura desde AdminExpress:

- Home dinámico;
- cupones;
- secciones de menú;
- grupos/opciones de modificadores;
- promos/precio comparativo/tags/patrocinado/destacado de producto;
- horario/pedido mínimo/tags/patrocinado de comercio.

Todos los RPC verifican `is_admin()`.

### 088 — actividad y personalización por país

`supabase/migrations/088_express_delivery_v2_country_activity_personalization.sql`

Agrega:

- `marketplace_my_orders_v2`: historial Delivery por país;
- `marketplace_delivery_notifications_v2`: bandeja Delivery por país;
- `marketplace_delivery_extras_v2`: cupones visibles + preferencias de
  historial dentro del país actual;
- RPC admin para leer/configurar venta cruzada por producto.

## 5. App Flutter

Entrada V2:

- `lib/express_delivery_v2_page.dart`
- `lib/connected_experience.dart` enruta módulo `market` a
  `ExpressDeliveryV2Page`.
- La pantalla V1 se conserva en el repositorio para comparación/rollback.

### Inicio

- selector de dirección;
- selector de país/zona;
- centro de notificaciones;
- carrito persistente;
- búsqueda de comercios y productos;
- banners;
- categorías;
- carruseles horizontales;
- secciones configurables;
- sponsored / “Anuncio”;
- descuentos;
- skeleton loading;
- “según tus preferencias” usando historial del país activo.

### Navegación Delivery

Barra propia:

1. Inicio
2. Mercados
3. Promos
4. Pedidos
5. Perfil

### Categorías

Pantalla independiente por categoría con:

- ordenar;
- descuentos;
- Express Plus;
- tiempo máximo;
- tags de producto/plato;
- productos de múltiples comercios;
- listado de comercios.

### Comercio

- portada;
- rating;
- ETA;
- envío;
- Plus;
- tabs Menú / Opiniones / Información;
- secciones internas del menú;
- horario;
- pedido mínimo.

### Producto

- ficha completa;
- precio normal/promocional;
- etiqueta de descuento;
- rating;
- grupos de opciones;
- mínimo/máximo/obligatorio;
- extras con costo;
- nota por producto;
- cantidad;
- venta cruzada;
- reseñas de producto.

### Carrito

- líneas separadas por combinación de extras/notas;
- cantidades;
- subtotal;
- recomendaciones;
- acceso persistente.

### Checkout “Último paso”

- dirección guardada;
- geocodificación mediante el picker existente de Express;
- indicaciones al repartidor;
- nota separada al comercio;
- presets: puerta / llamada / conserjería / dejar en puerta;
- propina rápida adaptada a moneda;
- prioridad;
- cupón;
- efectivo / transferencia-QR / online según zona;
- facturación separada por país;
- donación opcional;
- resumen estructurado.

### Pedidos

- historial filtrado por país;
- código seguro de entrega;
- calificación verificada del comercio;
- calificación verificada de producto.

### Notificaciones

- bandeja visual Delivery;
- filtro por país;
- pedidos, promociones, Plus y avisos;
- marcado como leído.

## 6. AdminExpress

Panel nuevo:

`lib/admin_delivery_v2.dart`

Entrada:

**Express Delivery · Experiencia V2**

Permite:

- filtrar por zona;
- crear/editar secciones Home;
- programar fecha/hora inicio/fin;
- crear/editar cupones;
- definir vigencia de cupones;
- secciones internas de menú;
- grupos de opciones y extras;
- promociones de producto con vigencia;
- tags;
- destacado;
- anuncio patrocinado;
- venta cruzada;
- horario JSON de comercio;
- pedido mínimo;
- apertura manual.

Preview y Producción mantienen switches/visibilidad separados.

## 7. Seguridad

Principios V2:

- nuevas tablas sensibles con RLS;
- config de Marketplace sin SELECT directo de cliente: acceso por RPC;
- facturación: own-user;
- RPC cliente: `auth.uid()` + cuenta activa;
- RPC admin: `is_admin()`;
- execute revocado a `PUBLIC` y `anon` en RPC nuevos;
- códigos PIN guardados como hash SHA-256;
- cupón validado por zona/país, vigencia y límites;
- modificadores revalidados en backend;
- precios finales se recalculan en backend;
- el cliente no puede imponer precio/modificador arbitrario.

## 8. QA realizado antes de Preview

Todo el QA SQL se ejecutó dentro de `BEGIN ... ROLLBACK`.

Validado:

- Iquique → CL / CLP;
- Trinidad → BO / BOB;
- cupón de Iquique rechazado en Trinidad;
- modificador requerido bloquea carrito incompleto;
- snapshot de extras/nota se guarda en order item;
- país del pedido se deriva de zona;
- PIN 6 dígitos se emite y valida por hash;
- PIN correcto cambia a delivered;
- pedidos CL no aparecen al consultar BO;
- pedidos BO no aparecen al consultar CL;
- notificaciones CL no aparecen en BO;
- cupón CL no aparece entre cupones de Trinidad;
- `anon` sin execute en RPC de pedidos V2;
- Production Marketplace permanece OFF en Iquique y Trinidad.

Flutter:

- app validada con `flutter analyze` y `flutter build web` en workflow
  específico de la rama;
- AdminExpress validado con analyze/build específico de rama.

## 9. Política de cancelación/reembolso

V2 no inventa cargos ni porcentajes comerciales.

El sistema existente conserva la cancelación básica de Marketplace/Delivery.
Antes de automatizar reembolsos o penalizaciones se debe configurar una matriz
aprobada por negocio para:

- actor (cliente/comercio/repartidor);
- estado;
- permitido/no permitido;
- cargo;
- porcentaje de devolución;
- comportamiento del proveedor de pago.

No se debe simular un reembolso de Mercado Pago/VeriPagos sin confirmación del
proveedor.

## 10. Rollback

Antes de Preview:

- volver App a
  `backup/pre-express-delivery-v2-2026-10-03`;
- volver AdminExpress a
  `backup/pre-express-delivery-v2-2026-10-03`;
- no aplicar migraciones 085–088.

Después de aplicar migraciones en Preview/backend compartido:

- las migraciones son aditivas y conservan estructuras V1;
- restaurar la entrada Flutter V1 si fuera necesario;
- dejar flags V2/Marketplace de Producción OFF;
- no eliminar tablas/columnas V2 hasta confirmar que no existen datos creados
  por Preview que deban conservarse.

## 11. Regla de despliegue

1. completar candidate SHA;
2. QA verde;
3. pedir autorización explícita;
4. aplicar 085–088;
5. publicar App a Preview;
6. publicar Admin en un Preview aislado o, si no existe, mantenerlo sin tocar
   el panel público;
7. revisión humana completa;
8. solo después de aprobación, preparar Producción.

**Nunca promover automáticamente Preview a Producción.**
