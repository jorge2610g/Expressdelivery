# Compartir viaje en vivo — Express

> **Estado:** LIVE en Web; backend aplicado y verificado; código fusionado a `main` y desplegado  
> **Fecha:** 2026-10-11  
> **Ámbito:** Flutter compartido + Web pública + Supabase compartido con aislamiento por `channel`  
> **Producción Web:** commit `87690395cda4e7a3d8de49bb142ff7e905c60b55`, workflow `38179612866` (build + deploy GitHub Pages: success)

## Objetivo

Cuando el pasajero toca **Compartir** durante un viaje activo, Express debe generar un enlace temporal que pueda enviarse a familiares o contactos. El receptor abre el enlace sin iniciar sesión y ve únicamente el seguimiento necesario del viaje mientras siga activo.

URL pública:

`https://expressviajes.online/?trip_share=<token>`

## Seguridad

- El token público contiene 32 bytes aleatorios codificados en hexadecimal.
- El token sin hash se devuelve una sola vez al pasajero; la base guarda solo SHA-256.
- La creación exige usuario autenticado, propiedad del viaje, canal autorizado y `app_settings.share_trip_enabled=true`.
- La lectura pública no expone IDs internos, teléfonos, pasajero, PIN, tarifa, billetera, pagos ni credenciales.
- El enlace deja de entregar ubicación cuando el viaje queda `completed` o `cancelled`, cuando se revoca o al vencer el TTL máximo de 12 horas.
- Preview y Producción comparten el mismo código y la misma tabla, pero cada enlace nace desde el `channel` autoritativo del viaje y la cuenta debe tener acceso a ese runtime.
- `trip_share_links` tiene RLS habilitado y no permite acceso directo a `anon` ni `authenticated`; la lectura pública pasa únicamente por `get_shared_trip(token)`.
- Los RPC expuestos en `public` son `SECURITY INVOKER`. La lógica privilegiada vive en el esquema no expuesto `trip_share_private` como `SECURITY DEFINER`, siguiendo la separación recomendada para evitar bypass privilegiado directamente en el Data API.

## Backend

Migraciones aplicadas al proyecto oficial `zgpijrznvaskgcmauwxx`:

- `supabase/migrations/20261011221500_trip_share_live_links.sql`
- `supabase/migrations/20261011222500_trip_share_rpc_security_hardening.sql`

Objetos:

- `public.trip_share_links`
- `public.create_trip_share_link(uuid,text)` — wrapper `SECURITY INVOKER`
- `public.get_shared_trip(text)` — wrapper `SECURITY INVOKER`
- `trip_share_private.create_trip_share_link_impl(uuid,text)` — implementación privilegiada no expuesta
- `trip_share_private.get_shared_trip_impl(text)` — implementación privilegiada no expuesta

Estados considerados activos:

- `driver_assigned`
- `driver_arriving`
- `driver_waiting`
- `in_progress`
- `emergency`

## Flutter

- `ExpressService.createTripShareLink` solicita el token al backend.
- `shareExpressTrip` incluye el enlace en el mensaje de WhatsApp; si no puede abrir WhatsApp, copia el mensaje con el enlace.
- `web_preview.dart` detecta `trip_share` antes del login y monta la vista pública.
- `PublicTripSharePage` consulta `get_shared_trip` cada 10 segundos mientras la página está en primer plano.
- El mapa público usa el fallback OSM del proveedor existente y muestra conductor + punto relevante (recogida o destino).

## Estado de publicación

- PR #165 fusionada a `main`.
- `Express Single App - Web First QA` en PR: success.
- Workflow de producción `Deploy Flutter Web to GitHub Pages` run `38179612866`: build `success` y deploy `success`.
- Artifact `github-pages` id `11716433767`, asociado al SHA `87690395cda4e7a3d8de49bb142ff7e905c60b55`.
- Queda como comprobación operativa manual generar un link desde un viaje activo y abrirlo en incógnito; esta prueba no requiere cambios de código.

## QA mínimo

1. Crear enlace desde una cuenta Preview con viaje activo.
2. Abrir el enlace en una sesión incógnita sin autenticación.
3. Confirmar nombre de conductor, vehículo, origen/destino y ubicación viva.
4. Mover al conductor y verificar refresco automático.
5. Completar/cancelar el viaje y confirmar que el enlace deja de mostrar ubicación.
6. Repetir con una cuenta Producción autorizada sin mezclar datos entre canales.
7. Verificar que un token inválido no revela si existe un viaje.
8. Ejecutar `flutter analyze`, `flutter test` y `flutter build web --release --target lib/web_preview.dart`.
9. Advisors después del hardening: no deben quedar warnings de `SECURITY DEFINER` para los RPC públicos de trip-share. El INFO `rls_enabled_no_policy` de `trip_share_links` es intencional porque no existe acceso directo para roles cliente.

## No cambiar

- No hacer públicas las tablas `trips`, `driver_profiles`, `users` ni `driver_vehicles`.
- No incluir teléfonos, PIN, pagos o datos del pasajero en el RPC público.
- No convertir el token en un ID de viaje predecible.
- No permitir que el cliente elija otro `channel` para un viaje que no le pertenece.
