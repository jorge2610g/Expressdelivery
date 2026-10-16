-- Opt-in por token Android para ofertas flotantes de Firebase.
-- Valor seguro: FALSE para todos los dispositivos existentes y nuevos.
-- La notificación FCM normal sigue activa hasta que el cliente soporte
-- explícitamente la recepción de datos en el motor de fondo.
alter table public.native_push_tokens
  add column if not exists floating_offer_enabled boolean not null default false;

comment on column public.native_push_tokens.floating_offer_enabled is
  'Opt-in exclusivo de este token Android para ofertas flotantes en segundo plano; no habilita Production por defecto.';

create or replace function public.clear_floating_offer_optin_on_token_transfer()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.user_id is distinct from old.user_id
     or new.channel is distinct from old.channel then
    new.floating_offer_enabled := false;
  end if;
  return new;
end;
$$;

drop trigger if exists native_push_floating_offer_owner_change
  on public.native_push_tokens;
create trigger native_push_floating_offer_owner_change
before update of user_id, channel on public.native_push_tokens
for each row
execute function public.clear_floating_offer_optin_on_token_transfer();

create or replace function public.set_native_push_floating_offer_enabled(
  p_token text,
  p_enabled boolean,
  p_channel text
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_channel text := public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if p_enabled is null
     or p_token is null
     or length(trim(p_token)) < 20 then
    raise exception 'Configuración de token inválida';
  end if;
  if v_channel = 'preview' and not public.is_active_audit_user(v_uid) then
    raise exception 'Preview requiere una cuenta de auditoría activa';
  end if;

  update public.native_push_tokens
     set floating_offer_enabled = p_enabled,
         updated_at = now()
   where user_id = v_uid
     and token = trim(p_token)
     and channel = v_channel
     and platform = 'android'
     and active = true;

  return found;
end;
$$;

revoke all on function public.set_native_push_floating_offer_enabled(text, boolean, text)
  from public, anon;
grant execute on function public.set_native_push_floating_offer_enabled(text, boolean, text)
  to authenticated;
