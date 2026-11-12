-- Quitar la ejecución pública de publish_verified_play_build(uuid).
--
-- La función inserta una fila en app_releases (la que consultan las actualizaciones
-- de la app), pero no comprueba quién la llama. Con los permisos por defecto de
-- Supabase, cualquier usuario anónimo o autenticado podía invocarla por RPC si
-- conocía el UUID de un build_jobs en estado ready.
--
-- Solo la usa el disparador trg_publish_verified_play_build, que es SECURITY DEFINER
-- y pertenece a postgres. No hay llamadas RPC en el repositorio ni en los workflows.
-- Después de este cambio, solo postgres y service_role pueden ejecutarla.

revoke all on function public.publish_verified_play_build(uuid)
  from public, anon, authenticated;
grant execute on function public.publish_verified_play_build(uuid)
  to service_role;
