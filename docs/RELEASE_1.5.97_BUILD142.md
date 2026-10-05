# Express 1.5.97 · build 142

Candidato Android con cobertura geográfica administrable.

## Alcance

- Países maestros administrables desde AdminExpress.
- Ciudades / zonas activas determinan la cobertura real por GPS.
- Fuera de cobertura, pasajero y nuevo registro de conductor quedan bloqueados con mensaje de disponibilidad.
- Registro de conductor exige ubicación dentro de la zona activa seleccionada.
- Didit se activa por país y admite configuración para futuros países sin modificar la app.
- Chile y Bolivia permanecen activos.
- Licencia y documentos adicionales siguen administrándose por país/zona.

## Backend

- Migración: `106_global_country_zone_coverage_controls.sql`.
- Tablas: `service_countries`, `identity_verification_country_settings`.
- RPC Admin: `admin_country_list`, `admin_upsert_country_coverage`, `admin_upsert_zone_v3`.
- RPC app: `submit_driver_onboarding_v2`.
- `service_zone_id_for_point` respeta país + zona activa.
- Didit Production/Sandbox resuelve el Workflow por ISO-2.

## Gate de release

Preview y Producción deben compilar el mismo SHA aprobado. No promover build 141: quedó anterior a estos cambios.
