# Fase 1: triggers de vencimiento (verificado contra producción, solo lectura)

## Versión vigente de cada función (huella md5 del cuerpo, 10/10 reproducidas localmente)
- `enforce_driver_offer_deadline` (015): `expires_at = created_at + 15 s` si `status='pending'`.
- `enforce_driver_offer_minimum_lifetime` (022): sube `expires_at` a `now() + 30 s` si es nulo o menor.
- `select_ride_offer` (vigente): modificada por 20261013072000 (parcel) y 20261013230700 (moneda). Acepta `expires_at` nulo.
- `select_ride_offer_v2` (089): envoltorio con canal.
- `same_operational_scope`: **versión de producción distinta del repositorio (deriva)**. Usa `account_runtime_bindings`.

## Cuándo se crea y modifica `expires_at` en `driver_offers`
- **Alta:** el cliente hace `upsert` (`lib/services/express_service.dart`) con `expires_at = ahora + offer_timeout_seconds`.
- **Triggers** (BEFORE INSERT y UPDATE OF created_at, expires_at, status): para pendientes, el de plazo fija 15 s y el de vida mínima lo sube a 30 s. El efecto final es **30 s desde la inserción**.
- **Re-oferta:** el `upsert` en conflicto reescribe `created_at` y vuelve a aplicar 30 s.
- **Estados no pendientes:** los triggers no tocan `expires_at`.
- `cleanup_expired_ride_offers`, `select_ride_offer`, `decline`, `cancel`, `admin_assign` solo cambian `status`.
- `renew_ride_request` cambia `expires_at` de la **solicitud** (3 min), no de la oferta.

## ¿Puede un trigger dejar una oferta pendiente sin vencimiento válido?
- **No por un trigger.** Cada INSERT o UPDATE de pendientes recibe un vencimiento no nulo y futuro. Verificado (T3).
- **Sí por bypass privilegiado** (`session_replication_role = replica`, solo superusuario): la fila queda con `expires_at` nulo (T4). Por eso la corrección v2 en el RPC es defensa en profundidad.

## Hallazgos que requieren decisión (no modificados)
1. **`offer_timeout_seconds` se ignora:** el ajuste de administración (10 a 600 s) no tiene efecto; la vigencia real es 30 s. **No cambiar sin consultar.**
2. **Deriva de `same_operational_scope`:** producción tiene una versión que no está en el repositorio.
3. **Parche anterior (`0eb7cb5`) obsoleto:** revertiría Envíos.
