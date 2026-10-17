# Auditoría de controles de Preview (Adminexpress) frente a lo que lee la app

Criterio: un módulo está **vivo** si una función de producción lo lee desde `admin_environment_config` o la app lo lee. Si no, el valor que guarda Preview **no lo usa nadie**.

| Módulo que escribe Preview | Leído por funciones de la base | Leído por la app | Estado |
|---|---|---|---|
| `app_settings` | `driver_floating_offer_config` (solo `driver_floating_offer_enabled`) | no | **Parcial.** Solo la oferta flotante está viva. Tiempos corregidos en PR Adminexpress #100. Resto de campos (moneda, tarifas mínimas, comisión, despacho, zona horaria, soporte) **muertos para la app**. |
| `service_zones` | `app_zone_context_v2` | no | Vivo (contexto de zonas de Preview). |
| `zone_services` | `app_zone_context_v2`, `app_zone_context_v3`, `driver_delivery_zone_enabled`, `express_parcel_zone_available` | no | Vivo. |
| `zone_payment_methods` | `zone_ride_payment_methods` | no | Vivo. |
| `zone_distance_fare_steps` | ninguna | no | **Muerto.** La tabla de producción **no tiene columna de canal** y las tarifas de distancia de Preview quedan en `admin_environment_config`. Prioridad alta: tarifas de zonas de prueba. |
| `fare_rules`, `special_fare_zones`, `service_zone_polygons`, `zone_payment_credentials`, `service_countries`, `service_catalog` | ninguna | no | **Muerto** para la app. |
| `driver_subscription_plans`, `driver_subscription_provider`, `driver_subscription_settings`, `driver_subscriptions`, `driver_document_requirements` | ninguna | no | **Muerto** para la app (el nombre coincide con tablas de producción, pero la app no lee el valor de Preview). |
| `partners`, `partner_members`, `partner_settlements`, `wallet_topups`, `security_zones` | ninguna | no | **Muerto** para la app. |

## Consecuencias
- Un administrador que edita estos valores en Preview **no ve efecto** en la app de prueba.
- Las tarifas de distancia y los pagos de zona de Preview **no están aislados**: o no llegan a la app, o usan la tabla compartida de producción.

## Recomendación (no implementada)
1. Preview no escribe en `admin_environment_config` para valores que la app no lea. Mostrar solo lectura con la fuente real.
2. Para zonas de prueba y sus tarifas: aislar por zona de prueba (filas dedicadas) en la tabla que la app realmente lee. Requiere decisión de diseño.
3. Revisar cada módulo muerto antes de retirar el control.
