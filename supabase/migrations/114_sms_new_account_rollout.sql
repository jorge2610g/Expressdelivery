-- SMS rollout compatibility: require verification for new accounts without
-- locking users and approved drivers that existed before activation.

alter table public.app_settings
  add column if not exists sms_verification_rollout_at timestamptz;

update public.app_settings
set sms_verification_rollout_at=coalesce(sms_verification_rollout_at,now()),
    updated_at=now()
where id=true;

update public.admin_environment_config
set payload=jsonb_set(
      payload,
      '{sms_verification_rollout_at}',
      to_jsonb(coalesce(nullif(payload->>'sms_verification_rollout_at','')::timestamptz,now())),
      true
    ),
    updated_at=now()
where environment='preview'
  and module='app_settings'
  and record_key='default';

create or replace function public.phone_verification_required_for_user(
  p_user_id uuid,
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
  v_requested boolean:=false;
  v_provider_ready boolean:=false;
  v_rollout_at timestamptz;
  v_created_at timestamptz;
  v_verified_at timestamptz;
begin
  if p_user_id is null then return false; end if;

  if v_channel='preview' then
    select c.payload into v_settings
    from public.admin_environment_config c
    where c.environment='preview'
      and c.module='app_settings'
      and c.record_key='default'
      and coalesce((c.payload->>'_deleted')::boolean,false)=false
    limit 1;
  else
    select to_jsonb(s) into v_settings
    from public.app_settings s where s.id=true limit 1;
  end if;

  v_requested:=case when v_role='driver'
    then coalesce((v_settings->>'sms_verification_driver_enabled')::boolean,false)
    else coalesce((v_settings->>'sms_verification_passenger_enabled')::boolean,false)
  end;
  if not v_requested then return false; end if;

  if v_channel='production' then
    select s.sms_provider_verified_at is not null
    into v_provider_ready
    from public.app_settings s where s.id=true;
    if not coalesce(v_provider_ready,false) then return false; end if;
  end if;

  begin
    v_rollout_at:=nullif(v_settings->>'sms_verification_rollout_at','')::timestamptz;
  exception when others then
    v_rollout_at:=null;
  end;
  if v_rollout_at is null then return false; end if;

  select u.created_at,u.phone_verified_at
  into v_created_at,v_verified_at
  from public.users u where u.id=p_user_id;

  if v_created_at is null then return false; end if;
  return v_created_at>=v_rollout_at or v_verified_at is not null;
end;
$$;

revoke all on function public.phone_verification_required_for_user(uuid,text,text)
from public,anon,authenticated;

create or replace function public.phone_verification_enabled(
  p_role text,
  p_channel text default 'production'
)
returns boolean
language plpgsql
stable security definer
set search_path=public
as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then return false; end if;
  return public.phone_verification_required_for_user(v_uid,p_role,p_channel);
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
declare v_verified timestamptz;
begin
  if public.phone_verification_required_for_user(new.passenger_id,'passenger',new.channel) then
    select u.phone_verified_at into v_verified from public.users u where u.id=new.passenger_id;
    if v_verified is null then
      raise exception 'Debes verificar tu teléfono antes de solicitar un viaje';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.enforce_driver_phone_verification_offer()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_verified timestamptz;
begin
  if public.phone_verification_required_for_user(new.driver_id,'driver',new.channel) then
    select u.phone_verified_at into v_verified from public.users u where u.id=new.driver_id;
    if v_verified is null then
      raise exception 'Debes verificar tu teléfono antes de enviar ofertas';
    end if;
  end if;
  return new;
end;
$$;

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
    begin
      v_channel:=public.normalize_runtime_channel(current_setting('app.runtime_channel',true));
    exception when others then
      v_channel:='production';
    end;
    if public.phone_verification_required_for_user(new.id,'driver',v_channel) then
      select u.phone_verified_at into v_verified from public.users u where u.id=new.id;
      if v_verified is null then
        raise exception 'Debes verificar tu teléfono antes de conectarte como conductor';
      end if;
    end if;
  end if;
  return new;
end;
$$;
