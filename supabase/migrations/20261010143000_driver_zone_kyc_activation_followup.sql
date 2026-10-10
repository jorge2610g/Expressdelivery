-- Follow-up for driver zone/KYC activation. Apply to QA before Production.
-- The prior migration 20261010130655 is already applied in QA, so this is
-- deliberately additive and preserves the immediately previous RPC definition.

create table if not exists public.admin_function_backup_20261010 (
  signature text primary key,
  definition text not null,
  acl text,
  backed_up_at timestamptz not null default now()
);

insert into public.admin_function_backup_20261010(signature, definition, acl)
select 'DZK-N1N2:' || p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid = 'public.admin_driver_activate(uuid, uuid, text)'::regprocedure
on conflict (signature) do nothing;

create or replace function public.admin_driver_activate(
  p_driver_id uuid,
  p_zone_id uuid default null,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_profile public.driver_profiles%rowtype;
  v_zone_id uuid;
  v_zone public.service_zones%rowtype;
  v_required integer;
  v_missing integer;
  v_identity public.driver_documents%rowtype;
  v_fallback_zone text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview', 'production') then raise exception 'Canal inválido'; end if;
  if v_channel = 'production' then perform public.admin_assert_environment('production'); end if;
  perform public.admin_assert_target_environment(p_driver_id, v_channel);
  select * into v_profile from public.driver_profiles where id = p_driver_id for update;
  if v_profile.id is null then raise exception 'Conductor no encontrado'; end if;

  select i.result ->> 'zone_id' into v_fallback_zone
  from public.identity_verifications i
  where i.user_id = p_driver_id and i.provider = 'express_manual' and i.subject_role = 'driver'
  order by i.created_at desc limit 1;
  v_zone_id := coalesce(p_zone_id, v_profile.zone_id,
    case when coalesce(v_fallback_zone, '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then v_fallback_zone::uuid end);
  if v_zone_id is null then raise exception 'Selecciona la zona del conductor'; end if;
  select * into v_zone from public.service_zones where id = v_zone_id;
  if v_zone.id is null or upper(coalesce(v_zone.country_code, '')) <> upper(coalesce(v_profile.country_code, '')) then
    raise exception 'Selecciona la zona del conductor';
  end if;

  select count(*), count(*) filter (where not exists (
    select 1 from public.driver_documents d
    where d.driver_id = p_driver_id and d.requirement_id = r.id and d.status = 'verified'
  )) into v_required, v_missing
  from public.driver_document_requirements r
  where r.active and r.required
    and (r.country_code is null or upper(r.country_code) = upper(v_profile.country_code))
    and (r.zone_id is null or r.zone_id = v_zone_id);
  if v_required = 0 or v_missing > 0 then raise exception 'Faltan fotografías por aprobar'; end if;

  select d.* into v_identity
  from public.driver_documents d join public.driver_document_requirements r on r.id = d.requirement_id
  where d.driver_id = p_driver_id and d.verification_method = 'manual'
    and lower(r.code) in ('identity_card', 'national_id', 'id_card', 'identity', 'carnet', 'cedula', 'cédula')
  order by d.updated_at desc limit 1;
  if v_identity.id is null or v_identity.status <> 'verified' or exists (
    select 1 from jsonb_each(v_identity.review_parts) as part(slot, value)
    where nullif(part.value ->> 'path', '') is not null
      and coalesce(part.value ->> 'status', 'pending') <> 'approved'
  ) then raise exception 'Faltan fotografías por aprobar'; end if;

  update public.driver_profiles set approval_status = 'approved', zone_id = v_zone.id,
    city = coalesce(v_zone.city, v_zone.name), updated_at = now()
  where id = p_driver_id;
  insert into public.notifications(user_id, title, body, type, channel, metadata)
  values (p_driver_id, 'Cuenta de conductor activada',
    'Ya puedes conectarte y recibir solicitudes en ' || coalesce(v_zone.city, v_zone.name) || '.',
    'driver_activation', v_channel,
    jsonb_build_object('zone_id', v_zone.id, 'channel', v_channel));
  perform public.admin_log_action('driver_activate', 'driver_profile', p_driver_id::text,
    jsonb_build_object('zone_id', v_zone.id, 'channel', v_channel));
  return jsonb_build_object('ok', true, 'driver_id', p_driver_id, 'zone_id', v_zone.id,
    'city', coalesce(v_zone.city, v_zone.name));
end;
$function$;

revoke execute on function public.admin_driver_activate(uuid, uuid, text) from public, anon;
grant execute on function public.admin_driver_activate(uuid, uuid, text) to authenticated;
