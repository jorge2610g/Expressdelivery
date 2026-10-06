alter table public.app_settings
  add column if not exists driver_floating_offer_enabled boolean not null default false;

update public.app_settings
set driver_floating_offer_enabled = false
where id = true;

insert into public.admin_environment_config(
  environment,
  module,
  record_key,
  payload,
  updated_at,
  updated_by
)
values(
  'preview',
  'app_settings',
  'default',
  jsonb_build_object('driver_floating_offer_enabled', true),
  now(),
  auth.uid()
)
on conflict(environment, module, record_key)
do update set
  payload = jsonb_set(
    coalesce(public.admin_environment_config.payload, '{}'::jsonb),
    '{driver_floating_offer_enabled}',
    'true'::jsonb,
    true
  ),
  updated_at = now();

create or replace function public.driver_floating_offer_config(
  p_channel text default 'production'
)
returns boolean
language plpgsql
stable
security definer
set search_path = 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel), ''), 'production'));
  v_enabled boolean := false;
begin
  if v_channel = 'preview' then
    select coalesce(
      c.payload -> 'driver_floating_offer_enabled' = 'true'::jsonb,
      false
    )
    into v_enabled
    from public.admin_environment_config c
    where c.environment = 'preview'
      and c.module = 'app_settings'
      and c.record_key = 'default'
    limit 1;
    return coalesce(v_enabled, false);
  end if;

  if v_channel <> 'production' then
    return false;
  end if;

  select coalesce(s.driver_floating_offer_enabled, false)
  into v_enabled
  from public.app_settings s
  where s.id = true
  limit 1;

  return coalesce(v_enabled, false);
end;
$function$;

revoke all on function public.driver_floating_offer_config(text) from public;
grant execute on function public.driver_floating_offer_config(text)
  to anon, authenticated;

create or replace function public.admin_driver_floating_offer_update(
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_enabled boolean := coalesce(p_enabled, false);
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.app_settings
  set driver_floating_offer_enabled = v_enabled,
      updated_at = now()
  where id = true;

  perform public.admin_log_action(
    'update',
    'app_settings',
    'driver_floating_offer_enabled',
    jsonb_build_object(
      'environment', 'production',
      'driver_floating_offer_enabled', v_enabled
    )
  );

  return v_enabled;
end;
$function$;

revoke all on function public.admin_driver_floating_offer_update(boolean) from public;
grant execute on function public.admin_driver_floating_offer_update(boolean)
  to authenticated;
