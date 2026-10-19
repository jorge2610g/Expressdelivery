# Regularización de `same_operational_scope` (propuesta, no aplicada)

## Referencia
- Definición **vigente de producción** (huella md5 `e074f411e6c88d4e7aa0d6340499dc61`). Cuerpo en `same_operational_scope_production.sql`.
- Versión del repositorio (035): huella distinta. **No es la de referencia.**

## Efecto de la regularización
- Si el cuerpo es idéntico, aplicarla **no cambia** el comportamiento en producción (se reemplaza por la misma lógica).
- **Antes de aplicar:** verificar con `pg_get_functiondef` que atributos (`stable`, `security definer`, `search_path`) coinciden con producción.

## Servicios afectados (13 funciones en producción)
- Taxi: `available_ride_requests_for_driver`, `select_ride_offer`, `admin_assign_ride`, `mark_ride_requests_viewed`, `notify_available_ride_to_drivers`, `notify_ride_offer`, `ride_request_matches_user_scope`, `nearby_online_driver_markers`.
- Envíos/Delivery: `available_deliveries_for_driver`, `available_deliveries_for_driver_v2`, `claim_delivery`, `create_delivery_driver_offer`, `admin_assign_delivery`.

## Aislamiento Preview/producción
- Producción decide por `account_runtime_bindings.environment`. Preview y producción **no se cruzan** en la matriz de 14 pares (`results_scope_matrix.txt`), salvo el caso de cuentas de producción con grupo de auditoría, que producción permite con cuentas de producción (correcto).
- La versión del repositorio **permitiría** que una cuenta de producción interactúe con una cuenta de Preview que cae en el grupo de auditoría. Por eso **no debe reemplazar** a producción.

## Condiciones antes de desplegar
1. Confirmar huella md5 y atributos de producción.
2. Pruebas de Taxi, Envíos y Delivery con la matriz de 14 pares.
3. Autorización explícita: la regularización es control de versiones, pero toca una función de aislamiento.
