# Riesgos antes de desplegar la v3 (no desplegada)

## Comportamiento que cambia para conductores y pasajeros
- Oferta: de ~30 s a 20 s (acordado).
- Solicitud vencida: ya no admite ofertas ni selección (cambio de comportamiento acordado).

## Riesgos de configuración
1. **Preview no aislado para tiempos:** `app_settings` es global; el panel Preview guarda en `admin_environment_config` y no tiene efecto. Decidir antes del despliegue.
2. **Caché de configuración:** hasta 45 s (y 10 min como máximo) para ver un cambio en búsqueda.
3. **Valor por defecto del panel (45 s)** distinto del valor real (20 s).

## Riesgos de verificación (no replicado localmente)
4. Triggers de producción no replicados: suscripción (`driver_subscription_offer_guard`), registro (`trg_log_*`), tarifas (`zzz_round_driver_offer_fare`, `zz_apply_special_fixed_fare`, `zzz_ride_recommended_fare_floor`), y guardas de Envíos (`guard_parcel_ride_offer_permission`, `guard_parcel_trip_assignment`). **Pueden rechazar o modificar ofertas**: validar en una rama de Supabase.
5. Permisos de vehículos de Envíos: no replicados; la prueba E1 cubre la aceptación pero no los permisos.
6. Dependencia del texto exacto de `select_ride_offer`: si cambia, el parche falla cerrado (es lo esperado).

## Riesgos de datos
7. Solicitudes vencidas sin limpieza programada: `cleanup_expired_ride_requests` no tiene programación en el repositorio. La aceptación queda protegida, pero los datos quedan en `searching`.
8. Ofertas pendientes existentes al desplegar: conservan su vigencia anterior (la v3 solo afecta altas y actualizaciones).

## Riesgo de deriva
9. `same_operational_scope` difiere entre producción y el repositorio (ver `SAME_OPERATIONAL_SCOPE_REGULARIZATION.md`).

## Requisitos para validar en Supabase (rama aislada, cuando se autorice)
- Aplicar v3 con todos los triggers reales.
- Probar vigencia por configuración (20 s, 120 s, límites).
- Solicitud vencida: insertar y seleccionar.
- Envíos de extremo a extremo con guardas y permisos.
- Concurrencia por API con dos conductores de auditoría.
- Desactivar notificaciones push en la rama.
- Tarifas y zonas sin cambios.
