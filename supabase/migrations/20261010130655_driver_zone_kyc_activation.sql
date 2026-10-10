-- Zona registrada del conductor y activación manual de KYC.
-- Aplicar primero en QA. No ejecutar la reparación de datos de docs/ops sin
-- autorización explícita del propietario.

create table if not exists public.admin_function_backup_20261010 (
  signature text primary key,
  definition text not null,
  acl text,
  backed_up_at timestamptz not null default now()
);

do $backup$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as signature, pg_get_functiondef(p.oid) as definition,
           p.proacl::text as acl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'set_driver_zone_from_location',
        'admin_driver_kyc_bolivia_manual_review_part',
        'admin_driver_kyc_bolivia_manual_list'
      )
  loop
    insert into public.admin_function_backup_20261010(signature, definition, acl)
    values ('DZK:' || r.signature, r.definition, r.acl)
    on conflict (signature) do nothing;
  end loop;
end
$backup$;

create or replace function public.set_driver_zone_from_location()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_zone uuid;
  v_city text;
begin
  -- zone_id is the registered operating zone. GPS may fill an empty zone,
  -- but must never overwrite or clear a zone selected by the driver/admin.
  if new.zone_id is null
     and new.latitude is not null
     and new.longitude is not null then
    v_zone := public.service_zone_id_for_point(new.latitude, new.longitude);
    if v_zone is not null then
      new.zone_id := v_zone;
      select city into v_city from public.service_zones where id = v_zone;
      if v_city is not null then new.city := v_city; end if;
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.admin_driver_kyc_bolivia_manual_review_part(
  p_document_id uuid,
  p_slot text,
  p_status text,
  p_reason text default null,
  p_expected_version integer default null,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_doc public.driver_documents%rowtype;
  v_slot text := lower(trim(coalesce(p_slot, '')));
  v_status text := lower(trim(coalesce(p_status, '')));
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_entry jsonb; v_current integer;
  v_new_doc public.driver_documents%rowtype;
  v_path text; v_country text; v_code text;
  v_previous text; v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_can_activate boolean := false;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview', 'production') then raise exception 'Canal inválido'; end if;
  if v_slot not in ('front', 'back', 'selfie', 'profile') then raise exception 'Fotografía inválida'; end if;
  if v_status not in ('approved', 'rejected', 'pending') then raise exception 'Estado inválido'; end if;
  if v_status = 'rejected' and length(coalesce(v_reason, '')) < 5 then raise exception 'Indica el motivo'; end if;
  select * into v_doc from public.driver_documents where id = p_document_id for update;
  if v_doc.id is null or v_doc.verification_method <> 'manual' then raise exception 'Documento no encontrado'; end if;
  select upper(p.country_code), lower(r.code) into v_country, v_code
  from public.driver_profiles p join public.driver_document_requirements r on r.id = v_doc.requirement_id
  where p.id = v_doc.driver_id;
  if v_code not in ('identity_card', 'national_id', 'id_card', 'identity', 'carnet', 'cedula', 'cédula') then
    raise exception 'Documento de identidad inválido';
  end if;
  perform public.admin_assert_target_environment(v_doc.driver_id, v_channel);
  v_entry := v_doc.review_parts -> v_slot;
  v_current := coalesce((v_entry ->> 'version')::integer, 0);
  if p_expected_version is null or v_current <> p_expected_version then
    raise exception 'La imagen fue actualizada. Refresca antes de decidir';
  end if;
  v_previous := coalesce(v_entry ->> 'status', 'pending');
  v_path := v_entry ->> 'path';
  if nullif(v_path, '') is null then raise exception 'No hay fotografía para revisar'; end if;
  if v_previous = v_status then
    return jsonb_build_object('ok', true, 'unchanged', true, 'status', v_doc.status);
  end if;

  update public.driver_documents set
    review_parts = jsonb_set(review_parts, array[v_slot],
      jsonb_build_object('status', v_status, 'reason',
        case when v_status = 'rejected' then left(v_reason, 600) else null end,
        'path', v_path, 'version', v_current + 1,
        'reviewed_at', now(), 'reviewed_by', auth.uid()), true),
    reviewed_at = now(), reviewed_by = auth.uid(), updated_at = now()
  where id = v_doc.id returning * into v_new_doc;

  insert into public.driver_manual_identity_review_history(
    document_id, actor_id, slot, from_status, to_status, from_version, to_version, reason, channel
  ) values (
    v_doc.id, auth.uid(), v_slot, v_previous, v_status, v_current, v_current + 1,
    case when v_status = 'rejected' then v_reason else null end, v_channel
  );
  update public.identity_verifications set
    status = v_new_doc.status, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now(),
    completed_at = case when v_new_doc.status = 'verified' then now() else completed_at end
  where id = (
    select i.id from public.identity_verifications i
    where i.user_id = v_doc.driver_id and i.provider = 'express_manual' and i.subject_role = 'driver'
    order by i.created_at desc limit 1
  );

  if v_status = 'rejected' then
    insert into public.notifications(user_id, title, body, type, channel, metadata)
    values (
      v_doc.driver_id, 'Corrige una fotografía',
      'Debes actualizar ' || case v_slot when 'front' then 'el frente del carné'
        when 'back' then 'el reverso del carné' when 'selfie' then 'tu selfie'
        else 'tu foto de perfil' end || '. ' || left(v_reason, 250),
      'driver_identity_review', v_channel,
      jsonb_build_object('route', 'driver_kyc_correction', 'document_id', v_doc.id,
        'slot', v_slot, 'status', v_status, 'review_version', v_current + 1,
        'channel', v_channel, 'deep_link', 'express://driver-kyc-correction/' || v_slot)
    );
  end if;

  select v_new_doc.status = 'verified' and not exists (
    select 1 from jsonb_each(v_new_doc.review_parts) as part(slot, value)
    where nullif(part.value ->> 'path', '') is not null
      and coalesce(part.value ->> 'status', 'pending') <> 'approved'
  ) into v_can_activate;
  perform public.admin_log_action('driver_kyc_photo_review', 'driver_document', v_doc.id::text,
    jsonb_build_object('slot', v_slot, 'from_status', v_previous, 'to_status', v_status, 'version', v_current + 1));
  return jsonb_build_object('ok', true, 'document_id', v_doc.id, 'slot', v_slot,
    'slot_status', v_status, 'document_status', v_new_doc.status, 'version', v_current + 1,
    'can_activate', v_can_activate);
end;
$function$;

create or replace function public.admin_driver_kyc_bolivia_manual_list(
  p_channel text default 'production',
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_channel text := lower(trim(coalesce(p_channel, '')));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview', 'production') then raise exception 'Canal inválido'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc), '[]'::jsonb)
    from (
      select d.id, d.driver_id, u.full_name, p.country_code,
        d.document_type, d.document_number, d.front_object_path, d.back_object_path,
        d.selfie_object_path, p.profile_photo_path, d.review_parts,
        d.status, d.rejection_reason, d.reviewed_by, d.reviewed_at,
        d.created_at, d.updated_at,
        p.zone_id, p.approval_status, z.name as zone_name
      from public.driver_documents d
      join public.driver_profiles p on p.id = d.driver_id
      join public.driver_document_requirements r on r.id = d.requirement_id
      left join public.users u on u.id = d.driver_id
      left join public.service_zones z on z.id = p.zone_id
      where d.verification_method = 'manual'
        and lower(coalesce(r.code, '')) in
          ('identity_card', 'national_id', 'id_card', 'identity', 'carnet', 'cedula', 'cédula')
        and public.is_active_audit_user(d.driver_id) = (v_channel = 'preview')
      order by case when d.status = 'rejected' then 0
                    when d.status = 'pending' then 1 else 2 end,
        d.created_at desc
      limit greatest(1, least(coalesce(p_limit, 100), 250))
    ) q
  );
end;
$function$;

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
  v_profile public.driver_profiles%rowtype;
  v_zone_id uuid;
  v_zone public.service_zones%rowtype;
  v_required integer;
  v_missing integer;
  v_identity public.driver_documents%rowtype;
  v_fallback_zone text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if lower(trim(coalesce(p_channel, ''))) not in ('preview', 'production') then raise exception 'Canal inválido'; end if;
  if lower(p_channel) = 'production' then perform public.admin_assert_environment('production'); end if;
  perform public.admin_assert_target_environment(p_driver_id, lower(p_channel));
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
  where r.active and r.required and upper(r.country_code) = upper(v_profile.country_code)
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
    'driver_activation', lower(p_channel),
    jsonb_build_object('zone_id', v_zone.id, 'channel', lower(p_channel)));
  perform public.admin_log_action('driver_activate', 'driver_profile', p_driver_id::text,
    jsonb_build_object('zone_id', v_zone.id, 'channel', lower(p_channel)));
  return jsonb_build_object('ok', true, 'driver_id', p_driver_id, 'zone_id', v_zone.id,
    'city', coalesce(v_zone.city, v_zone.name));
end;
$function$;

revoke execute on function public.admin_driver_activate(uuid, uuid, text) from public, anon;
grant execute on function public.admin_driver_activate(uuid, uuid, text) to authenticated;
