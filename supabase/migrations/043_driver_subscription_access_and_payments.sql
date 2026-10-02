
create or replace function public.driver_subscription_allows_dispatch(p_driver_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select case
    when not coalesce((select enforce_access from public.driver_subscription_settings where id=true), false)
      then true
    else exists (
      select 1 from public.driver_subscriptions s
      where s.driver_id=p_driver_id and s.status='active' and s.expires_at>now()
    )
  end;
$$;
grant execute on function public.driver_subscription_allows_dispatch(uuid) to authenticated;

create or replace function public.my_driver_subscription_state()
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_settings public.driver_subscription_settings%rowtype;
  v_sub public.driver_subscriptions%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  select * into v_settings from public.driver_subscription_settings where id=true;
  select * into v_sub from public.driver_subscriptions where driver_id=v_uid;
  if v_sub.plan_id is not null then
    select * into v_plan from public.driver_subscription_plans where id=v_sub.plan_id;
  end if;
  return jsonb_build_object(
    'feature_enabled',coalesce(v_settings.enabled,false),
    'enforce_access',coalesce(v_settings.enforce_access,false),
    'provider',coalesce(v_settings.provider,'veripagos'),
    'provider_enabled',coalesce(v_settings.provider_enabled,false),
    'qr_validity',coalesce(v_settings.qr_validity,'0/00:15'),
    'usable',coalesce(v_sub.status='active' and v_sub.expires_at>now(),false),
    'status',coalesce(v_sub.status,'inactive'),
    'plan_id',v_sub.plan_id,'plan_name',v_plan.name,'plan_code',v_plan.code,
    'started_at',v_sub.started_at,'expires_at',v_sub.expires_at,
    'remaining_seconds',case when v_sub.expires_at is null then 0
      else greatest(0,extract(epoch from (v_sub.expires_at-now()))::bigint) end
  );
end;
$$;
grant execute on function public.my_driver_subscription_state() to authenticated;

create or replace function public.admin_driver_subscriptions(p_search text default null)
returns table(
  driver_id uuid,full_name text,email text,phone text,
  approval_status text,online_status text,subscription_status text,
  plan_id bigint,plan_name text,started_at timestamptz,expires_at timestamptz,
  remaining_seconds bigint
)
language plpgsql stable security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return query
  select dp.id,coalesce(u.full_name,''),coalesce(au.email,''),coalesce(u.phone,''),
    dp.approval_status,dp.online_status,coalesce(ds.status,'inactive'),
    ds.plan_id,dsp.name,ds.started_at,ds.expires_at,
    case when ds.expires_at is null then 0::bigint
      else greatest(0,extract(epoch from (ds.expires_at-now()))::bigint) end
  from public.driver_profiles dp
  left join public.users u on u.id=dp.id
  left join auth.users au on au.id=dp.id
  left join public.driver_subscriptions ds on ds.driver_id=dp.id
  left join public.driver_subscription_plans dsp on dsp.id=ds.plan_id
  where coalesce(trim(p_search),'')=''
     or coalesce(u.full_name,'') ilike '%'||trim(p_search)||'%'
     or coalesce(au.email,'') ilike '%'||trim(p_search)||'%'
     or coalesce(u.phone,'') ilike '%'||trim(p_search)||'%'
  order by coalesce(ds.expires_at,'epoch'::timestamptz) desc,coalesce(u.full_name,au.email,'');
end;
$$;
revoke all on function public.admin_driver_subscriptions(text) from public;
grant execute on function public.admin_driver_subscriptions(text) to authenticated;

create or replace function public.admin_set_driver_subscription(
  p_driver_id uuid,p_plan_id bigint,p_expires_at timestamptz default null,p_notes text default null
)
returns public.driver_subscriptions
language plpgsql security definer set search_path=public as $$
declare
  v_plan public.driver_subscription_plans%rowtype;
  v_current public.driver_subscriptions%rowtype;
  v_result public.driver_subscriptions%rowtype;
  v_now timestamptz:=now();
  v_exp timestamptz;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select * into v_plan from public.driver_subscription_plans where id=p_plan_id;
  if not found then raise exception 'Plan no encontrado'; end if;
  select * into v_current from public.driver_subscriptions where driver_id=p_driver_id;
  v_exp:=coalesce(p_expires_at,v_now+make_interval(days=>v_plan.days));
  insert into public.driver_subscriptions(driver_id,plan_id,status,started_at,expires_at,updated_at)
  values(p_driver_id,v_plan.id,'active',v_now,v_exp,v_now)
  on conflict(driver_id) do update set
    plan_id=excluded.plan_id,status='active',started_at=v_now,expires_at=v_exp,updated_at=v_now
  returning * into v_result;
  insert into public.driver_subscription_history(
    driver_id,plan_id,action,previous_expires_at,new_expires_at,notes,created_by
  ) values(p_driver_id,v_plan.id,'admin_set',v_current.expires_at,v_exp,p_notes,auth.uid());
  return v_result;
end;
$$;
revoke all on function public.admin_set_driver_subscription(uuid,bigint,timestamptz,text) from public;
grant execute on function public.admin_set_driver_subscription(uuid,bigint,timestamptz,text) to authenticated;

create or replace function public.admin_set_driver_subscription_settings(
  p_enabled boolean,p_enforce_access boolean,p_provider_enabled boolean,p_qr_validity text default '0/00:15'
)
returns public.driver_subscription_settings
language plpgsql security definer set search_path=public as $$
declare v_result public.driver_subscription_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update public.driver_subscription_settings
  set enabled=coalesce(p_enabled,true),enforce_access=coalesce(p_enforce_access,false),
      provider_enabled=coalesce(p_provider_enabled,false),
      qr_validity=coalesce(nullif(trim(p_qr_validity),''),'0/00:15'),
      updated_at=now(),updated_by=auth.uid()
  where id=true returning * into v_result;
  if v_result.enforce_access then
    update public.driver_profiles dp
    set online_status='offline',updated_at=now()
    where dp.online_status='online' and not public.driver_subscription_allows_dispatch(dp.id);
  end if;
  return v_result;
end;
$$;
revoke all on function public.admin_set_driver_subscription_settings(boolean,boolean,boolean,text) from public;
grant execute on function public.admin_set_driver_subscription_settings(boolean,boolean,boolean,text) to authenticated;

create or replace function public.service_get_driver_subscription_provider_settings()
returns jsonb language sql stable security definer set search_path=private as $$
  select to_jsonb(s) from private.driver_subscription_provider_settings s where id=true;
$$;
revoke all on function public.service_get_driver_subscription_provider_settings() from public,anon,authenticated;
grant execute on function public.service_get_driver_subscription_provider_settings() to service_role;

create or replace function public.service_set_driver_subscription_provider_settings(
  p_api_base_url text,p_create_path text,p_status_path text,p_username text,
  p_password text,p_secret_key text,p_extra_config jsonb default '{}'::jsonb,p_updated_by uuid default null
)
returns void language plpgsql security definer set search_path=private as $$
begin
  insert into private.driver_subscription_provider_settings(
    id,provider,api_base_url,create_path,status_path,username,password,secret_key,
    extra_config,updated_at,updated_by
  ) values(
    true,'veripagos',nullif(trim(p_api_base_url),''),nullif(trim(p_create_path),''),
    nullif(trim(p_status_path),''),nullif(trim(p_username),''),nullif(p_password,''),
    nullif(p_secret_key,''),coalesce(p_extra_config,'{}'::jsonb),now(),p_updated_by
  )
  on conflict(id) do update set
    api_base_url=excluded.api_base_url,create_path=excluded.create_path,status_path=excluded.status_path,
    username=excluded.username,
    password=coalesce(excluded.password,private.driver_subscription_provider_settings.password),
    secret_key=coalesce(excluded.secret_key,private.driver_subscription_provider_settings.secret_key),
    extra_config=excluded.extra_config,updated_at=now(),updated_by=excluded.updated_by;
end;
$$;
revoke all on function public.service_set_driver_subscription_provider_settings(text,text,text,text,text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.service_set_driver_subscription_provider_settings(text,text,text,text,text,text,jsonb,uuid) to service_role;

create or replace function public.service_create_driver_subscription_payment(
  p_driver_id uuid,p_plan_id bigint,p_provider text default 'veripagos',p_expires_at timestamptz default null
)
returns public.driver_subscription_payments
language plpgsql security definer set search_path=public as $$
declare
  v_plan public.driver_subscription_plans%rowtype;
  v_existing public.driver_subscription_payments%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
begin
  select * into v_plan from public.driver_subscription_plans where id=p_plan_id and active=true;
  if not found then raise exception 'Plan no disponible'; end if;
  select * into v_existing from public.driver_subscription_payments
  where driver_id=p_driver_id and status='pending' and (expires_at is null or expires_at>now())
  order by created_at desc limit 1;
  if found then return v_existing; end if;
  insert into public.driver_subscription_payments(
    driver_id,plan_id,amount,currency_code,provider,status,expires_at
  ) values(
    p_driver_id,v_plan.id,v_plan.amount,v_plan.currency_code,
    coalesce(nullif(trim(p_provider),''),'veripagos'),'pending',
    coalesce(p_expires_at,now()+interval '15 minutes')
  ) returning * into v_payment;
  return v_payment;
end;
$$;
revoke all on function public.service_create_driver_subscription_payment(uuid,bigint,text,timestamptz) from public,anon,authenticated;
grant execute on function public.service_create_driver_subscription_payment(uuid,bigint,text,timestamptz) to service_role;

create or replace function public.service_update_driver_subscription_payment_provider(
  p_payment_id bigint,p_provider_order_id text,p_qr_payload text,
  p_provider_data jsonb default '{}'::jsonb,p_expires_at timestamptz default null
)
returns public.driver_subscription_payments
language plpgsql security definer set search_path=public as $$
declare v_payment public.driver_subscription_payments%rowtype;
begin
  update public.driver_subscription_payments
  set provider_order_id=coalesce(nullif(trim(p_provider_order_id),''),provider_order_id),
      qr_payload=coalesce(nullif(p_qr_payload,''),qr_payload),
      provider_data=coalesce(provider_data,'{}'::jsonb)||coalesce(p_provider_data,'{}'::jsonb),
      expires_at=coalesce(p_expires_at,expires_at),updated_at=now()
  where id=p_payment_id and status='pending'
  returning * into v_payment;
  return v_payment;
end;
$$;
revoke all on function public.service_update_driver_subscription_payment_provider(bigint,text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.service_update_driver_subscription_payment_provider(bigint,text,text,jsonb,timestamptz) to service_role;

create or replace function public.service_finalize_driver_subscription_payment(
  p_payment_id bigint,p_provider_order_id text default null,p_provider_data jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_payment public.driver_subscription_payments%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_current public.driver_subscriptions%rowtype;
  v_now timestamptz:=now(); v_base timestamptz; v_exp timestamptz; v_had_current boolean:=false;
begin
  select * into v_payment from public.driver_subscription_payments where id=p_payment_id for update;
  if not found then raise exception 'Pago no encontrado'; end if;
  if v_payment.status='approved' then
    select * into v_current from public.driver_subscriptions where driver_id=v_payment.driver_id;
    return jsonb_build_object('approved',true,'already_approved',true,'expires_at',v_current.expires_at);
  end if;
  if v_payment.status<>'pending' then raise exception 'El pago ya no está pendiente'; end if;
  select * into v_plan from public.driver_subscription_plans where id=v_payment.plan_id;
  if not found then raise exception 'Plan no encontrado'; end if;
  select * into v_current from public.driver_subscriptions where driver_id=v_payment.driver_id for update;
  v_had_current:=found;
  v_base:=case when v_had_current and v_current.status='active' and v_current.expires_at>v_now
    then v_current.expires_at else v_now end;
  v_exp:=v_base+make_interval(days=>v_plan.days);
  update public.driver_subscription_payments
  set status='approved',paid_at=coalesce(paid_at,v_now),
      provider_order_id=coalesce(nullif(trim(p_provider_order_id),''),provider_order_id),
      provider_data=coalesce(provider_data,'{}'::jsonb)||coalesce(p_provider_data,'{}'::jsonb),
      updated_at=v_now where id=v_payment.id;
  insert into public.driver_subscriptions(driver_id,plan_id,status,started_at,expires_at,last_payment_id,updated_at)
  values(v_payment.driver_id,v_plan.id,'active',v_now,v_exp,v_payment.id,v_now)
  on conflict(driver_id) do update set
    plan_id=excluded.plan_id,status='active',
    started_at=case when public.driver_subscriptions.status='active'
      and public.driver_subscriptions.expires_at>v_now
      then public.driver_subscriptions.started_at else v_now end,
    expires_at=v_exp,last_payment_id=v_payment.id,updated_at=v_now;
  insert into public.driver_subscription_history(
    driver_id,plan_id,payment_id,action,previous_expires_at,new_expires_at,amount,notes
  ) values(v_payment.driver_id,v_plan.id,v_payment.id,'payment_approved',
    case when v_had_current then v_current.expires_at else null end,
    v_exp,v_payment.amount,'VeriPagos');
  return jsonb_build_object('approved',true,'already_approved',false,
    'driver_id',v_payment.driver_id,'plan_id',v_plan.id,'plan_name',v_plan.name,'expires_at',v_exp);
end;
$$;
revoke all on function public.service_finalize_driver_subscription_payment(bigint,text,jsonb) from public,anon,authenticated;
grant execute on function public.service_finalize_driver_subscription_payment(bigint,text,jsonb) to service_role;

create or replace function public.service_cancel_driver_subscription_payment(
  p_payment_id bigint,p_status text default 'cancelled',p_provider_data jsonb default '{}'::jsonb
)
returns public.driver_subscription_payments
language plpgsql security definer set search_path=public as $$
declare v_payment public.driver_subscription_payments%rowtype;
begin
  if p_status not in ('cancelled','expired','rejected') then raise exception 'Estado inválido'; end if;
  update public.driver_subscription_payments
  set status=p_status,cancelled_at=case when p_status='cancelled' then now() else cancelled_at end,
      provider_data=coalesce(provider_data,'{}'::jsonb)||coalesce(p_provider_data,'{}'::jsonb),updated_at=now()
  where id=p_payment_id and status='pending' returning * into v_payment;
  return v_payment;
end;
$$;
revoke all on function public.service_cancel_driver_subscription_payment(bigint,text,jsonb) from public,anon,authenticated;
grant execute on function public.service_cancel_driver_subscription_payment(bigint,text,jsonb) to service_role;

create or replace function public.enforce_driver_subscription_online()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.online_status='online' and coalesce(old.online_status,'') is distinct from 'online'
    and not public.driver_subscription_allows_dispatch(new.id)
  then raise exception 'Tu suscripción no está activa'; end if;
  return new;
end;
$$;
drop trigger if exists driver_subscription_online_guard on public.driver_profiles;
create trigger driver_subscription_online_guard
before update of online_status on public.driver_profiles
for each row execute function public.enforce_driver_subscription_online();

create or replace function public.enforce_driver_subscription_offer()
returns trigger language plpgsql set search_path=public as $$
begin
  if not public.driver_subscription_allows_dispatch(new.driver_id)
  then raise exception 'Tu suscripción no está activa'; end if;
  return new;
end;
$$;
drop trigger if exists driver_subscription_offer_guard on public.driver_offers;
create trigger driver_subscription_offer_guard
before insert on public.driver_offers
for each row execute function public.enforce_driver_subscription_offer();

do $$
begin
  begin alter publication supabase_realtime add table public.driver_subscriptions;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.driver_subscription_payments;
  exception when duplicate_object then null; end;
end $$;
