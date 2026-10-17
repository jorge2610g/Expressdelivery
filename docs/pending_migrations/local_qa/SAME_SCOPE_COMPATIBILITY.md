# Compatibilidad de la regularización de `same_operational_scope`

## Firma
- Producción: `(p_user_a uuid, p_user_b uuid) returns boolean`. Sin cambio en la regularización propuesta.
- Las 13 funciones llaman con dos `uuid` y esperan `boolean`: **no cambia el contrato**.

## Por qué la regularización no cambia el comportamiento
- El cuerpo propuesto es idéntico al de producción (md5 `e074f411…`, verificado localmente).
- Sustituir una función por un cuerpo idéntico no altera ninguno de los llamadores.
- **Condición:** confirmar con `pg_get_functiondef` que los atributos (`stable`, `security definer`, `search_path`) coinciden antes de aplicar.

## Funciones afectadas (13)
Taxi: `available_ride_requests_for_driver`, `select_ride_offer`, `admin_assign_ride`, `mark_ride_requests_viewed`, `notify_available_ride_to_drivers`, `notify_ride_offer`, `ride_request_matches_user_scope`, `nearby_online_driver_markers`.
Envíos/Delivery: `available_deliveries_for_driver`, `available_deliveries_for_driver_v2`, `claim_delivery`, `create_delivery_driver_offer`, `admin_assign_delivery`.

## Aislamiento Preview/producción (matriz de 14 pares)
- Ver `results_scope_matrix.txt`. La versión de producción bloquea el cruce de una cuenta de producción con una cuenta de Preview que cae en el grupo de auditoría.
- La versión del repositorio (035) **no** lo bloquea. Por eso no se debe usar como referencia.

## Lo que no verifica esta prueba
- Zonas: el aislamiento de zonas no lo hace esta función (lo hacen `zone_id` y el canal en cada consulta).
- Ejecución real de las 13 funciones: requieren tablas y datos no replicados localmente.

## Decisión
- No reemplazar la función vigente. La propuesta `20261017_regularize_same_operational_scope_PROPOSAL.sql` solo regulariza el repositorio con el cuerpo de producción.
