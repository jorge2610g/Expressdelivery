# Revisión de seguridad · funciones SECURITY DEFINER expuestas · 2026-10-10

- **Proyecto:** `zgpijrznvaskgcmauwxx` (producción). Solo lectura: no se aplicó ningún cambio.
- **Estado:** hallazgos documentados. **Ninguna corrección aplicada.** Cualquier migración requiere autorización explícita del propietario.

## Conteos (verificados por el advisor y por consulta)
- Ejecutables por `anon`: **11**. Ejecutables por `authenticated`: **374**. Todas en `public`.
- Clasificación por lectura de cuerpos: (a) validación literal 332; (a') validación indirecta 15; (b) sin validación aparente 16; (c) sistema que no debería ser RPC pública 9; (d) dudosa 2.
- Las funciones trigger SECURITY DEFINER no son ejecutables por `anon` ni `authenticated`.

## Hallazgos prioritarios

### H1 · ALTO (verificado) · bloqueo de cuentas por cualquier anónimo
- `public.auth_login_guard_record_failure(p_email text)` es ejecutable por `anon` y `authenticated`.
- Solo valida que el email contenga `@`. Cada llamada suma un fallo por hash SHA-256 del email. A los 3 fallos deja `locked_at`.
- **Efecto:** cualquiera puede bloquear el inicio de sesión de una cuenta conociendo su email, sin contraseña.

### H2 · MEDIO (verificado) · consulta anónima del estado de bloqueo
- `public.auth_login_guard_state(p_email text)` es ejecutable por `anon`. Devuelve si un email está bloqueado y cuántos intentos lleva.
- La clave es SHA-256 sin sal de un email en minúsculas. Es enumerable para emails conocidos.

### H3 · MEDIO (leído, no verificado en vivo) · helpers RLS con IDs arbitrarios
- `can_read_user_profile(uuid, uuid)`, `ride_request_matches_user_scope`, `same_operational_scope`, `is_ride_request_passenger`, entre otros, aceptan IDs arbitrarios.
- Un `authenticated` puede averiguar si dos usuarios comparten viaje o delivery.

### H4 · MEDIO (leído) · consultas de otros usuarios sin validar al llamador
- `driver_subscription_allows_dispatch(uuid)`, `is_active_audit_user(uuid)`, `admin_user_runtime_environment(uuid)`: responden para cualquier ID.

### H5 · BAJO · `cleanup_expired_ride_offers()` y `cleanup_expired_ride_requests()`
- Cualquier usuario activo puede ejecutarlas. Falta leer el alcance completo del cuerpo.

## Opciones de corrección (decisión del propietario)
1. **H1/H2:** revocar `EXECUTE` de `anon` y `authenticated` sobre ambas funciones, y que solo las llame la Edge Function de login con `service_role`, con límite de intentos por IP. Requiere revisar cómo la app llama hoy al login antes de revocar, para no romperlo.
2. **H3/H4:** validar que el llamador sea el propio ID o tenga relación legítima antes de responder; o mover los helpers a esquema privado no expuesto por la API.
3. **H5:** leer el cuerpo; si solo limpia filas vencidas, pasarlo a `service_role` o a un job programado.

## Antes de cualquier cambio
- Respaldo: exportar `pg_get_functiondef` y los `acl` actuales de las 385 funciones (como en E6).
- Probar primero en QA `xbphilqezmwfjfpdbwad` y verificar el flujo de login de Preview.
- Autorización explícita del propietario para aplicar en producción.

## Pendiente de verificar
- Cuerpo completo de `cleanup_expired_*`, `special_fare_for_route` y `app_zone_context_v2`.
- Cómo llama la app al login (qué RPC se invoca antes de autenticar).
