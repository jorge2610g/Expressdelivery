-- SMS verification hardening + fair driver priority rollout.
-- Applied live on 2026-10-05.

alter table public.service_countries
  add column if not exists calling_code text;

update public.service_countries
set calling_code = case country_code
  when 'CL' then '+56'
  when 'BO' then '+591'
  when 'BR' then '+55'
  when 'AR' then '+54'
  else calling_code
end
where country_code in ('CL','BO','BR','AR');

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='service_countries_calling_code_format_check'
      and conrelid='public.service_countries'::regclass
  ) then
    alter table public.service_countries
      add constraint service_countries_calling_code_format_check
      check (
        calling_code is null
        or calling_code ~ '^\+[1-9][0-9]{0,3}$'
      );
  end if;
end
$$;

alter table public.app_settings
  add column if not exists sms_provider_verified_at timestamptz;

create or replace function public.phone_country_catalog()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'country_code',c.country_code,
        'name',c.name,
        'calling_code',c.calling_code
      )
      order by c.name
    ),
    '[]'::jsonb
  )
  from public.service_countries c
  where c.active=true
    and nullif(trim(coalesce(c.calling_code,'')),'') is not null;
$$;

revoke all on function public.phone_country_catalog()
from public;
grant execute on function public.phone_country_catalog()
to anon, authenticated;

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

create or replace function public.protect_verified_phone_state()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.phone is distinct from old.phone
     and new.phone_verified_at is not distinct from old.phone_verified_at then
    new.phone_verified_at:=null;
    new.phone_country_code:=null;
  end if;
  return new;
end;
$$;

drop trigger if exists users_clear_verification_on_phone_change
on public.users;

create trigger users_clear_verification_on_phone_change
before update of phone
on public.users
for each row
execute function public.protect_verified_phone_state();

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
  v_requested boolean:=false;
  v_provider_ready boolean:=false;
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
    v_requested:=coalesce(
      (v_settings->>'sms_verification_driver_enabled')::boolean,
      false
    );
  else
    v_requested:=coalesce(
      (v_settings->>'sms_verification_passenger_enabled')::boolean,
      false
    );
  end if;

  if not v_requested then return false; end if;
  if v_channel='preview' then return true; end if;

  select s.sms_provider_verified_at is not null
  into v_provider_ready
  from public.app_settings s
  where s.id=true;

  return coalesce(v_provider_ready,false);
end;
$$;

revoke all on function public.phone_verification_enabled(text,text)
from public,anon;
grant execute on function public.phone_verification_enabled(text,text)
to authenticated;

create or replace function public.admin_country_list()
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'country_code',c.country_code,
          'name',c.name,
          'currency_code',c.currency_code,
          'calling_code',c.calling_code,
          'active',c.active,
          'driver_registration_enabled',c.driver_registration_enabled,
          'didit_enabled',coalesce(v.didit_enabled,false),
          'manual_fallback_enabled',coalesce(v.manual_fallback_enabled,true),
          'production_workflow_configured',
            nullif(trim(coalesce(v.production_workflow_id,'')),'') is not null,
          'sandbox_workflow_configured',
            nullif(trim(coalesce(v.sandbox_workflow_id,'')),'') is not null,
          'zones_total',(select count(*) from public.service_zones z where upper(coalesce(z.country_code,''))=c.country_code),
          'zones_active',(select count(*) from public.service_zones z where upper(coalesce(z.country_code,''))=c.country_code and z.active=true)
        )
        order by c.name
      ),
      '[]'::jsonb
    )
    from public.service_countries c
    left join public.identity_verification_country_settings v
      on v.country_code=c.country_code
  );
end;
$$;

create or replace function public.admin_upsert_country_coverage_v2(
  p_country_code text,
  p_name text,
  p_currency_code text,
  p_calling_code text,
  p_active boolean,
  p_driver_registration_enabled boolean,
  p_didit_enabled boolean,
  p_manual_fallback_enabled boolean default true,
  p_production_workflow_id text default null,
  p_sandbox_workflow_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_code text:=upper(trim(coalesce(p_country_code,'')));
  v_calling text:=trim(coalesce(p_calling_code,''));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_code !~ '^[A-Z]{2}$' then raise exception 'Código ISO de país inválido'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nombre de país requerido'; end if;
  if upper(trim(coalesce(p_currency_code,''))) !~ '^[A-Z]{3}$' then
    raise exception 'Código de moneda inválido';
  end if;
  if v_calling !~ '^\+[1-9][0-9]{0,3}$' then
    raise exception 'Prefijo telefónico internacional inválido';
  end if;

  insert into public.service_countries(
    country_code,name,currency_code,calling_code,
    active,driver_registration_enabled,updated_at
  )
  values(
    v_code,trim(p_name),upper(trim(p_currency_code)),v_calling,
    coalesce(p_active,false),coalesce(p_driver_registration_enabled,true),now()
  )
  on conflict(country_code) do update set
    name=excluded.name,
    currency_code=excluded.currency_code,
    calling_code=excluded.calling_code,
    active=excluded.active,
    driver_registration_enabled=excluded.driver_registration_enabled,
    updated_at=now();

  insert into public.identity_verification_country_settings(
    country_code,didit_enabled,manual_fallback_enabled,
    production_workflow_id,sandbox_workflow_id,updated_at
  )
  values(
    v_code,coalesce(p_didit_enabled,false),
    coalesce(p_manual_fallback_enabled,true),
    nullif(trim(coalesce(p_production_workflow_id,'')),''),
    nullif(trim(coalesce(p_sandbox_workflow_id,'')),''),
    now()
  )
  on conflict(country_code) do update set
    didit_enabled=excluded.didit_enabled,
    manual_fallback_enabled=excluded.manual_fallback_enabled,
    production_workflow_id=coalesce(
      nullif(trim(coalesce(p_production_workflow_id,'')),''),
      identity_verification_country_settings.production_workflow_id
    ),
    sandbox_workflow_id=coalesce(
      nullif(trim(coalesce(p_sandbox_workflow_id,'')),''),
      identity_verification_country_settings.sandbox_workflow_id
    ),
    updated_at=now();

  return jsonb_build_object(
    'ok',true,'country_code',v_code,'calling_code',v_calling,
    'active',coalesce(p_active,false),
    'driver_registration_enabled',coalesce(p_driver_registration_enabled,true),
    'didit_enabled',coalesce(p_didit_enabled,false)
  );
end;
$$;

revoke all on function public.admin_upsert_country_coverage_v2(
  text,text,text,text,boolean,boolean,boolean,boolean,text,text
) from public,anon;
grant execute on function public.admin_upsert_country_coverage_v2(
  text,text,text,text,boolean,boolean,boolean,boolean,text,text
) to authenticated;

update public.app_settings
set sms_verification_passenger_enabled=true,
    sms_verification_driver_enabled=true,
    updated_at=now()
where id=true;

update public.admin_environment_config
set payload=jsonb_set(
      jsonb_set(payload,'{sms_verification_passenger_enabled}','true'::jsonb,true),
      '{sms_verification_driver_enabled}','true'::jsonb,true
    ),
    updated_at=now()
where environment='preview' and module='app_settings' and record_key='default';

update public.driver_priority_settings
set preview_enabled=true,
    production_enabled=true,
    preview_enforcement_enabled=true,
    production_enforcement_enabled=true,
    updated_at=now()
where id=true;

update public.admin_environment_config
set payload=payload || jsonb_build_object(
      'preview_enabled',true,
      'preview_enforcement_enabled',true,
      'production_enabled',true,
      'production_enforcement_enabled',true,
      'updated_at',now()
    ),
    updated_at=now()
where environment='preview'
  and module='driver_priority_settings'
  and record_key='default';

create or replace function public.available_ride_requests_for_driver_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_s jsonb;
  v_enabled boolean:=false;
  v_enforcement boolean:=false;
  v_priority jsonb;
  v_level text:='medium';
  v_base jsonb;
  v_lat numeric;
  v_lng numeric;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_s:=public.driver_priority_settings_for(v_channel);
  v_enabled:=case when v_channel='preview'
    then coalesce((v_s->>'preview_enabled')::boolean,false)
    else coalesce((v_s->>'production_enabled')::boolean,false)
  end;
  v_enforcement:=case when v_channel='preview'
    then coalesce((v_s->>'preview_enforcement_enabled')::boolean,false)
    else coalesce((v_s->>'production_enforcement_enabled')::boolean,false)
  end;

  select coalesce(jsonb_agg(e),'[]'::jsonb)
  into v_base
  from jsonb_array_elements(
    coalesce(public.available_ride_requests_for_driver(),'[]'::jsonb)
  ) e
  where public.normalize_runtime_channel(e->>'channel')=v_channel;

  if coalesce(v_enabled,false) is false
     or coalesce(v_enforcement,false) is false then
    return v_base;
  end if;

  v_priority:=public.driver_priority_summary_for_v2(v_uid,v_channel);
  v_level:=coalesce(v_priority->>'level','medium');

  select latitude,longitude into v_lat,v_lng
  from public.driver_profiles where id=v_uid;

  select coalesce(
    jsonb_agg(x.payload order by x.rank_a,x.rank_b,x.rank_c,x.created_at),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      e as payload,
      coalesce((e->>'created_at')::timestamptz,now()) as created_at,
      case
        when v_level in ('high','medium') then coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),99999)
        else 0
      end as rank_a,
      case
        when v_level='high' then -coalesce(pr.passenger_rating,5)
        else 0
      end as rank_b,
      case
        when v_level in ('high','medium') then -coalesce(
          nullif(e->>'proposed_fare','')::numeric
          / nullif(nullif(e->>'route_distance_km','')::numeric,0),0
        )
        else 0
      end as rank_c
    from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) e
    left join lateral (
      select round(avg(r.score)::numeric,2) as passenger_rating
      from public.ratings r
      where r.to_user_id=nullif(e->>'passenger_id','')::uuid
        and r.rated_role='passenger'
    ) pr on true
  ) x;

  return coalesce(v_result,'[]'::jsonb);
end;
$$;
