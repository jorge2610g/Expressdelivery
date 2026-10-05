-- Require a fresh Supabase Auth OTP before marking a profile verified or proving the SMS provider.

create or replace function public.sync_my_verified_phone(
  p_country_code text,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text:=upper(trim(coalesce(p_country_code,'')));
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_phone text;
  v_confirmed_at timestamptz;
  v_calling_code text;
begin
  if v_uid is null then
    raise exception 'Sesión requerida';
  end if;

  select nullif(trim(u.phone),''),
         u.phone_confirmed_at
  into v_phone,v_confirmed_at
  from auth.users u
  where u.id=v_uid;

  if v_phone is null or v_confirmed_at is null then
    raise exception 'El teléfono todavía no fue confirmado por Supabase Auth';
  end if;

  if v_confirmed_at < now() - interval '15 minutes' then
    raise exception 'La confirmación del teléfono expiró. Solicita un código nuevo';
  end if;

  if v_phone !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'El teléfono confirmado no está en formato internacional válido';
  end if;

  select c.calling_code
  into v_calling_code
  from public.service_countries c
  where c.country_code=v_country
    and c.active=true
    and nullif(trim(coalesce(c.calling_code,'')),'') is not null;

  if v_calling_code is null then
    raise exception 'País no habilitado para verificación de teléfono';
  end if;

  if left(v_phone,length(v_calling_code))<>v_calling_code then
    raise exception 'El teléfono confirmado no coincide con el país seleccionado';
  end if;

  update public.users
  set phone=v_phone,
      phone_country_code=v_country,
      phone_verified_at=v_confirmed_at,
      updated_at=now()
  where id=v_uid;

  if not found then
    raise exception 'Perfil de usuario no encontrado';
  end if;

  update public.app_settings
  set sms_provider_verified_at=coalesce(sms_provider_verified_at,now()),
      updated_at=now()
  where id=true;

  return jsonb_build_object(
    'ok',true,
    'channel',v_channel,
    'phone',v_phone,
    'country_code',v_country,
    'phone_verified_at',v_confirmed_at,
    'sms_provider_verified',true
  );
end;
$$;

revoke all on function public.sync_my_verified_phone(text,text)
from public,anon;
grant execute on function public.sync_my_verified_phone(text,text)
to authenticated;
