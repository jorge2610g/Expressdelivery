-- PROPUESTA, NO APLICADA. Requiere autorización explícita del propietario y validación en Supabase.
--
-- Objetivo: guardar por TOKEN del dispositivo el estado efectivo de la barra de ofertas:
--   floating_offer_enabled = permiso de superposición concedido AND opción «Ventana flotante de ofertas» activa.
-- Y una marca de tiempo propia de la comprobación del permiso (permission_checked_at), que la
-- función de push usa en lugar de last_seen_at. Una app cerrada no informa cambios de permiso,
-- así que un estado viejo se trata como desconocido y el envío vuelve a ser notificación normal.
--
-- Seguridad: solo el dueño del token (auth.uid()) puede actualizarlo; la marca de tiempo la pone el
-- servidor (now()), no el cliente.
--
-- Rollback: alter table public.native_push_tokens drop column permission_checked_at;
--           drop function public.set_push_token_overlay_state(text, boolean);

alter table public.native_push_tokens
  add column if not exists permission_checked_at timestamptz;

create or replace function public.set_push_token_overlay_state(
  p_token text,
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_rows integer := 0;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  update public.native_push_tokens
  set floating_offer_enabled = coalesce(p_enabled, false),
      permission_checked_at = now(),
      updated_at = now()
  where token = p_token
    and user_id = v_uid
    and platform = 'android';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$fn$;

revoke all on function public.set_push_token_overlay_state(text, boolean) from public;
grant execute on function public.set_push_token_overlay_state(text, boolean) to authenticated;
