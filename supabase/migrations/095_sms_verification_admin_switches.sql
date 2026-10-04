-- Admin-controlled SMS phone verification rollout.
-- Both roles default OFF so Production can launch before Twilio is enabled.

alter table public.app_settings
  add column if not exists sms_verification_passenger_enabled boolean not null default false,
  add column if not exists sms_verification_driver_enabled boolean not null default false;

update public.app_settings
set sms_verification_passenger_enabled =
      coalesce(sms_verification_passenger_enabled,false),
    sms_verification_driver_enabled =
      coalesce(sms_verification_driver_enabled,false)
where id=true;

-- Keep Preview independent and OFF unless an admin explicitly enables it.
update public.admin_environment_config
set payload =
      jsonb_set(
        jsonb_set(
          payload,
          '{sms_verification_passenger_enabled}',
          coalesce(payload->'sms_verification_passenger_enabled','false'::jsonb),
          true
        ),
        '{sms_verification_driver_enabled}',
        coalesce(payload->'sms_verification_driver_enabled','false'::jsonb),
        true
      ),
    updated_at=now()
where environment='preview'
  and module='app_settings'
  and record_key='default';

create or replace function public.admin_phone_verification_settings_update(
  p_passenger_enabled boolean,
  p_driver_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.app_settings
  set sms_verification_passenger_enabled =
        coalesce(p_passenger_enabled,false),
      sms_verification_driver_enabled =
        coalesce(p_driver_enabled,false),
      updated_at=now()
  where id=true
  returning to_jsonb(app_settings.*) into v_result;

  perform public.admin_log_action(
    'update',
    'phone_verification_settings',
    'global',
    jsonb_build_object(
      'passenger_enabled',coalesce(p_passenger_enabled,false),
      'driver_enabled',coalesce(p_driver_enabled,false)
    )
  );

  return v_result;
end;
$$;

revoke all on function
  public.admin_phone_verification_settings_update(boolean,boolean)
from public,anon;
grant execute on function
  public.admin_phone_verification_settings_update(boolean,boolean)
to authenticated;

create or replace function public.phone_verification_enabled(
  p_role text,
  p_channel text default 'production'
)
returns boolean
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_role text:=lower(coalesce(trim(p_role),'passenger'));
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_settings jsonb;
begin
  if v_channel='preview' then
    select c.payload
    into v_settings
    from public.admin_environment_config c
    where c.environment='preview'
      and c.module='app_settings'
      and c.record_key='default'
      and coalesce((c.payload->>'_deleted')::boolean,false)=false
    limit 1;
  else
    select to_jsonb(s)
    into v_settings
    from public.app_settings s
    where s.id=true
    limit 1;
  end if;

  if v_role='driver' then
    return coalesce(
      (v_settings->>'sms_verification_driver_enabled')::boolean,
      false
    );
  end if;

  return coalesce(
    (v_settings->>'sms_verification_passenger_enabled')::boolean,
    false
  );
end;
$$;

revoke all on function public.phone_verification_enabled(text,text)
from public,anon;
grant execute on function public.phone_verification_enabled(text,text)
to authenticated;

create or replace function public.enforce_passenger_phone_verification()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_verified timestamptz;
begin
  if public.phone_verification_enabled('passenger',new.channel) then
    select u.phone_verified_at
    into v_verified
    from public.users u
    where u.id=new.passenger_id;

    if v_verified is null then
      raise exception
        'Debes verificar tu teléfono antes de solicitar un viaje';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ride_requests_require_verified_phone
on public.ride_requests;
create trigger ride_requests_require_verified_phone
before insert
on public.ride_requests
for each row execute function public.enforce_passenger_phone_verification();

create or replace function public.enforce_driver_phone_verification_offer()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_verified timestamptz;
begin
  if public.phone_verification_enabled('driver',new.channel) then
    select u.phone_verified_at
    into v_verified
    from public.users u
    where u.id=new.driver_id;

    if v_verified is null then
      raise exception
        'Debes verificar tu teléfono antes de enviar ofertas';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists driver_offers_require_verified_phone
on public.driver_offers;
create trigger driver_offers_require_verified_phone
before insert or update
on public.driver_offers
for each row execute function public.enforce_driver_phone_verification_offer();

create or replace function public.enforce_driver_phone_verification_online()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_verified timestamptz;
  v_channel text:='production';
begin
  if new.online_status='online'
     and old.online_status is distinct from new.online_status then
    -- Driver profile itself is shared. Use the user's current application
    -- runtime when available; Production is the safe default.
    begin
      v_channel:=public.normalize_runtime_channel(
        current_setting('app.runtime_channel',true)
      );
    exception when others then
      v_channel:='production';
    end;

    if public.phone_verification_enabled('driver',v_channel) then
      select u.phone_verified_at
      into v_verified
      from public.users u
      where u.id=new.id;

      if v_verified is null then
        raise exception
          'Debes verificar tu teléfono antes de conectarte como conductor';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists driver_profiles_require_verified_phone_online
on public.driver_profiles;
create trigger driver_profiles_require_verified_phone_online
before update of online_status
on public.driver_profiles
for each row execute function public.enforce_driver_phone_verification_online();
