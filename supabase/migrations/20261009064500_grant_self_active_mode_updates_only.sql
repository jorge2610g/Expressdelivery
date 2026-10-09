-- Express: permitir cambio Pasajero <-> Conductor con la cuenta actual.
-- 2026-10-09. Probado primero en Supabase Preview xbphilqezmwfjfpdbwad.
--
-- La APK existente actualiza public.users(active_mode, updated_at) directamente.
-- Existe RLS users_update_self, pero falta GRANT UPDATE: error 42501.
--
-- Seguridad:
-- * NO se otorga UPDATE sobre toda la tabla users.
-- * Solo se pueden modificar active_mode y updated_at.
-- * users_update_self impide cambiar cuentas ajenas (auth.uid() = id).
-- * guard_user_driver_mode_transition bloquea salida de Conductor con
--   viaje/delivery activo y actualiza online_status a offline.
-- * El acceso a dispatch continúa condicionado a aprobación de conductor.
-- * No se cambian contraseñas, teléfonos ni estados administrativos.
--
-- Ejecutar primero en Preview; trasladar a Producción únicamente después
-- de QA y la aprobación de promoción (jamás copiar usuarios reales/QA).

DO $migration_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'users'
       AND policyname = 'users_update_self'
       AND cmd = 'UPDATE'
       AND 'authenticated' = ANY(roles)
  ) THEN
    RAISE EXCEPTION 'Abortado: falta la política RLS users_update_self';
  END IF;
END;
$migration_check$;

GRANT UPDATE (active_mode, updated_at)
  ON TABLE public.users TO authenticated;

DO $migration_verify$
BEGIN
  IF NOT has_column_privilege('authenticated', 'public.users', 'active_mode', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.users', 'updated_at', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.users', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.users', 'account_status', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.users', 'phone_verified_at', 'UPDATE')
  THEN
    RAISE EXCEPTION 'Abortado: permisos UPDATE de public.users no son mínimos';
  END IF;
END;
$migration_verify$;
