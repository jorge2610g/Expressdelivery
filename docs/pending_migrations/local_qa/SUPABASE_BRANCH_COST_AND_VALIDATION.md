# Costo estimado de una rama de prueba y casos que requieren Supabase

## Proyecto
- Proyecto de producción: `Express Production`, región `ca-central-1`, **PostgreSQL 17.6** (metadatos del proyecto, solo lectura).
- Las pruebas locales corren en **PostgreSQL 15**: diferencia a tener en cuenta.

## Costo (provisional, no confirmado)
- Fuentes de terceros indican unos **0,01344 USD por hora** para una rama de tamaño Micro. La página oficial de precios no lo confirmó en la búsqueda realizada.
- Estimación para una prueba de **2 horas**: unos 0,03 USD en Micro, más cualquier cargo mínimo de cómputo del plan. Con tamaños mayores el costo sube.
- **No se aceptó ningún cargo ni se creó la rama.** El intento anterior fue rechazado en la confirmación de costo.
- Antes de autorizar: verificar la tarifa vigente de ramas y tamaños en el panel del proyecto (sección de facturación o ramas).

Fuentes consultadas (para verificar):
- Página oficial: https://supabase.com/docs/pricing
- Resumen de terceros: https://schematichq.com/blog/supabase-pricing
- Resumen de terceros 2026: https://toolradar.com/blog/supabase-pricing-2026
- Comparativa de ramas: https://xata.io/blog/neon-vs-supabase-vs-xata-postgres-branching-part-2

## Casos que requieren Supabase (no reproducibles localmente)
1. Aplicar v3 con **todos** los triggers reales (suscripción, registro de eventos, tarifas y guardas de Envíos).
2. Vigencia con la configuración real: 20 s, 120 s y límites del RPC de administración.
3. Solicitud vencida: inserción y selección con triggers reales.
4. Envíos de extremo a extremo: permisos de vehículos y grants de conductor.
5. Concurrencia por API con dos conductores de auditoría y una solicitud de prueba (plan en `PLAN_api_concurrency.md`).
6. Desactivar notificaciones push en la rama para no enviar FCM.
7. Tarifas y zonas sin cambios.
8. Ejecutar `close_stale_ride_requests` sobre datos de prueba (`20261017_close_stale_ride_requests_PROPOSAL.sql`).
9. Confirmar `service_role` y permisos de funciones en PostgreSQL 17.
