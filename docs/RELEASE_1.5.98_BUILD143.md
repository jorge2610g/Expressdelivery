# Express 1.5.98 · build 143

Candidato Android con cobertura geográfica y operativa administrable.

## Incluye

- Países maestros administrables desde AdminExpress.
- Zonas/cities determinan cobertura real por GPS.
- Fuera de cobertura: pasajero y registro de conductor quedan bloqueados.
- Registro nuevo de conductor exige GPS dentro de la zona activa.
- Didit se activa/desactiva por país y admite Workflow por ISO-2.
- Al desactivar un país o zona, conductores conectados pasan a offline.
- Un conductor solo puede conectarse dentro de su zona activa.
- Ofertas de viajes y delivery respetan país/zona activa.
- Producción muestra un mensaje claro de “Zona no disponible”.
- Cobertura usa el mismo resolvedor para radio y polígonos.

## Backend

- `106_global_country_zone_coverage_controls.sql`
- `107_operational_coverage_hardening.sql`
- Didit Production/Sandbox generalizado por país.

## Release gate

Preview y Producción deben usar exactamente el mismo SHA aprobado de la app.
Los builds 141 y 142 quedan obsoletos para este cambio.
