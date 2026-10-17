# same_operational_scope: producción frente a GitHub (solo lectura)

## Versión que funciona en producción
- Lógica por **entorno vinculado** (`account_runtime_bindings.environment`). Si no hay vínculo, el entorno es `preview` si la cuenta está en un grupo de auditoría activo y habilitado; si no, `production`.
- Reglas: entornos distintos → falso. Entorno `production` → verdadero. Entorno `preview` → verdadero solo si ambas cuentas están en el mismo grupo de auditoría activo.
- Huella: `e074f411e6c88d4e7aa0d6340499dc61`. Reproducida y verificada en local. Cuerpo completo: `same_operational_scope_production.sql`.

## Versión del repositorio (migración 035)
- Lógica solo por **grupo de auditoría**: sin grupo en ambos → verdadero; grupo distinto o ausente en uno → falso.
- **No tiene noción de entorno vinculado.** Es anterior a `account_runtime_bindings`.

## Diferencia (no está en el repositorio: deriva)
La versión de producción no tiene origen en ninguna migración del repositorio. Probablemente se aplicó fuera del control de versiones. No puedo determinar desde aquí quién la aplicó.

## Matriz de comparación (14 pares, `results_scope_matrix.txt`)
| Par | Producción | Repositorio |
|---|---|---|
| prod con grupo G1 ↔ prod sin grupo | verdadero | falso |
| prod con grupo G1 ↔ sin vínculo sin grupo | verdadero | falso |
| prod con grupo G1 ↔ sin vínculo en G1 | **falso** | **verdadero** |
| preview G1 ↔ sin vínculo en G1 | verdadero | verdadero |
| resto (8 pares) | igual | igual |

**El caso crítico** es `prod con grupo G1 ↔ sin vínculo en G1`: el repositorio permite que una cuenta de **producción** interactúe con una cuenta que cae en **preview**. Producción lo bloquea. **Producción es la versión correcta para el aislamiento.**

## Servicios que dependen de esta función (13 funciones en producción)
- **Taxi:** `available_ride_requests_for_driver`, `select_ride_offer`, `admin_assign_ride`, `mark_ride_requests_viewed`, `notify_available_ride_to_drivers`, `notify_ride_offer`, `ride_request_matches_user_scope`, `nearby_online_driver_markers` (mapa).
- **Envíos / Delivery:** `available_deliveries_for_driver`, `available_deliveries_for_driver_v2`, `claim_delivery`, `create_delivery_driver_offer`, `admin_assign_delivery`.

## Recomendación
- **No reemplazar la función de producción** por la versión del repositorio. Introduciría la fuga de aislamiento descrita.
- **Sí regularizar el repositorio** con la versión de producción (cambio solo de control de versiones, sin desplegar). La reproducción local ya la usa (`same_operational_scope_production.sql`).
- Antes de cualquier cambio en esta función, probar Taxi, Envíos y Delivery con la matriz completa.
