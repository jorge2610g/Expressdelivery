# Verificación de solo lectura de la migración 20261017004342 (offer_lifetime_v3)

Fecha: 2026-10-17. Proyecto: Express Production. Solo consultas de lectura.

## Migración
- Figura en el historial de migraciones como `20261017004342_offer_lifetime_v3`.

## Huellas (md5 del cuerpo) después de aplicar
| Función | Huella | Estado |
|---|---|---|
| enforce_driver_offer_deadline | cee251087cfbcfc6f62def8145a065fb | coincide con la versión aprobada |
| enforce_driver_offer_minimum_lifetime | 94d3cac9abae33647c0b00cb0368230e | coincide con la versión aprobada |
| select_ride_offer | 9262427282c4edb10fae4c877b791dc6 | coincide con la versión aprobada |
| driver_offer_expires_at | existe | nueva |
| same_operational_scope | e074f411e6c88d4e7aa0d6340499dc61 | sin cambio (versión segura vigente) |

Huellas anteriores (recuperación): ver `recovery/CHECKSUMS.sha256` y `recovery/RESTORE_previous_definitions.sql`.

## Triggers
- trg_driver_offer_deadline: BEFORE INSERT OR UPDATE OF created_at, expires_at, status (sin cambio).
- trg_enforce_driver_offer_minimum_lifetime: BEFORE INSERT OR UPDATE OF expires_at, status (sin cambio).

## Configuración
- offer_timeout_seconds = 20. search_timeout_seconds = 180. Sin cambio.

## Compatibilidad
- select_ride_offer conserva la rama de Envíos (`v_mode = 'parcel'`) y la guarda de vigencia de la solicitud.
- Ofertas de los últimos 7 días que superan el vencimiento de su solicitud: 0.
- Ofertas creadas desde la aplicación: 0 (sin tráfico de conductores tras la aplicación; la prueba de comportamiento en vivo queda pendiente).
- Solicitudes abiertas: 0. Ofertas pendientes: 0. Viajes: 85 (sin cambio).

## Errores de la aplicación
- Desde la aplicación de la migración: 8 registros, todos avisos de Flutter sobre ListTile (cosmético, no relacionados con la migración).
- Últimas 24 horas: avisos de ListTile (366), eventos de mensajería (113), permisos push (88), registro de tokens (84), transiciones de viaje (73), llamadas ZEGO (69) y fallos de app_lifecycle_listener (57, pendiente de investigar en la app).

## Estado
- Aplicada y verificada en estructura (funciones, triggers, configuración). Comportamiento en vivo: pendiente de tráfico real.
