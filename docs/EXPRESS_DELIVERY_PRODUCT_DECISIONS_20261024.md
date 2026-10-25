# Decisión vigente de Delivery Express — 2026-10-24

Esta nota registra la dirección de producto indicada por el propietario y sustituye los planes históricos que enviaban el reparto comercial a una app `Express_Repartidor`.

## Conductores

- Taxistas, repartidores de paquetería y repartidores de pedidos comerciales usan Express Principal (`com.express.usuario1`).
- Las ofertas comerciales entran en las mismas listas, avisos y flujo actual de recogida/entrega. No se rediseñan las pantallas del conductor; solo se identifica el servicio como restaurante.
- El permiso existente `market` autoriza ofertas comerciales. El backend conserva la autorización por cuenta, zona y contexto y valida oferta/aceptación; el cliente no concede permisos.
- El permiso `parcel` sigue limitado a envíos entre personas.
- Comprobación de solo lectura al backend de Production: `available_deliveries_for_driver_v2` y `create_delivery_driver_offer` revisan `driver_work_permission_allowed`, zona y separación `parcel/market`; el trigger `trg_driver_delivery_claim_permissions` está habilitado. No hace falta cambiar el contrato SQL para abrir este flujo al cliente.
- La cola actual consulta ofertas cada 12 s mientras la pantalla del conductor está activa. No se confirmó un push en segundo plano específico para ofertas comerciales; queda pendiente antes de prometer la misma entrega de notificaciones fuera de la app.

## Comercios

- Express Restaurante es una app distinta de operación del comercio, basada en `https://expressviajes.online/restaurantes/` y los módulos de pedidos, catálogo y liquidaciones existentes.
- La app reutiliza RPC, RLS, autenticación y datos actuales. No copia la app Express Principal ni incorpora permisos administrativos.
- La web `/restaurantes/` se conserva mientras Android completa la QA de cuentas de comercio, operaciones y callback Auth.
- La primera app Android ya tiene scaffold y módulos funcionales. Falta instalarla en un emulador/dispositivo, validar cuenta Preview y callback Supabase; push Firebase y firma de release siguen pendientes.

## Despliegue

Los cambios de esta implementación permanecen en ramas locales hasta la revisión y publicación autorizada. No se migró ni modificó Production para habilitar estas funciones durante la implementación.
