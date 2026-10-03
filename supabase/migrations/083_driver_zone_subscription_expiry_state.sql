-- Normalize expired driver-zone subscriptions in the state returned to the app.
create or replace function public.my_driver_subscription_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_zone_name text;
  v_zone_enabled boolean:=false;
  v_zone_enforce boolean:=false;
  v_global public.driver_subscription_settings%rowtype;
  v_sub public.driver_zone_subscriptions%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_usable boolean:=false;
  v_display_status text:='inactive';
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;

  select dp.zone_id,z.zone_key,z.name
  into v_zone_id,v_zone_key,v_zone_name
  from public.driver_profiles dp
  left join public.service_zones z on z.id=dp.zone_id
  where dp.id=v_uid;

  select * into v_global
  from public.driver_subscription_settings
  where id=true;

  if v_zone_id is not null then
    select enabled,enforce_access
    into v_zone_enabled,v_zone_enforce
    from public.driver_subscription_zone_settings
    where zone_id=v_zone_id;

    select * into v_sub
    from public.driver_zone_subscriptions
    where driver_id=v_uid
      and zone_id=v_zone_id;
  end if;

  if v_sub.plan_id is not null then
    select * into v_plan
    from public.driver_subscription_plans
    where id=v_sub.plan_id;
  end if;

  v_usable:=coalesce(
    v_sub.status='active'
    and v_sub.expires_at>now()
    and v_plan.zone_key=v_zone_key,
    false
  );

  v_display_status:=case
    when v_usable then 'active'
    when v_sub.status='active'
      and v_sub.expires_at is not null
      and v_sub.expires_at<=now()
    then 'expired'
    else coalesce(v_sub.status,'inactive')
  end;

  return jsonb_build_object(
    'feature_enabled',coalesce(v_zone_enabled,false),
    'enforce_access',coalesce(v_zone_enforce,false),
    'provider',coalesce(v_global.provider,'veripagos'),
    'provider_enabled',coalesce(v_global.provider_enabled,false),
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15'),
    'zone_id',v_zone_id,
    'zone_key',v_zone_key,
    'zone_name',v_zone_name,
    'usable',v_usable,
    'status',v_display_status,
    'plan_id',v_sub.plan_id,
    'plan_name',v_plan.name,
    'plan_code',v_plan.code,
    'plan_zone_key',v_plan.zone_key,
    'started_at',v_sub.started_at,
    'expires_at',v_sub.expires_at,
    'remaining_seconds',case
      when v_sub.expires_at is null then 0
      else greatest(
        0,
        extract(epoch from(v_sub.expires_at-now()))::bigint
      )
    end
  );
end;
$function$;

revoke execute on function public.my_driver_subscription_state()
from public,anon;
grant execute on function public.my_driver_subscription_state()
to authenticated;
