-- E4 · 2026-10-10 · Aprobación automática del conductor (decisión del propietario).
-- Problema: aprobar frente/reverso/selfie dejaba la identidad `verified`, pero
-- driver_profiles.approval_status seguía `pending` ("en revisión") hasta un
-- segundo clic manual que el flujo no pedía.
--
-- Regla: tras una revisión administrativa, el conductor pasa a `approved`
-- solo si:
--   * approval_status = 'pending' (nunca reactiva rejected/suspended);
--   * tiene country_code y existe ≥1 requisito activo+obligatorio para su país
--     (global o de su zona);
--   * cada requisito activo+obligatorio tiene un documento `verified`;
--   * admin_set_driver_approval (reutilizada) valida además la identidad manual
--     más reciente, notifica al conductor y registra auditoría.
-- Se ejecuta solo desde RPC administrativas con canal validado; no hay trigger,
-- así que un conductor no puede auto-aprobarse.
-- Rollback: docs/backups/20261010_E4_rollback.sql

create or replace function public.driver_auto_approve_if_complete(p_driver_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile public.driver_profiles%rowtype;
  v_required int;
  v_missing int;
begin
  if p_driver_id is null or not public.is_admin() then
    return false;
  end if;
  select * into v_profile from public.driver_profiles where id = p_driver_id;
  if v_profile.id is null or v_profile.approval_status <> 'pending'
     or nullif(trim(coalesce(v_profile.country_code, '')), '') is null then
    return false;
  end if;

  select count(*),
         count(*) filter (where not exists (
           select 1 from public.driver_documents d
           where d.driver_id = p_driver_id
             and d.requirement_id = r.id
             and d.status = 'verified'))
  into v_required, v_missing
  from public.driver_document_requirements r
  where r.active and r.required
    and upper(r.country_code) = upper(v_profile.country_code)
    and (r.zone_id is null or r.zone_id = v_profile.zone_id);

  if v_required = 0 or v_missing > 0 then
    return false;
  end if;

  begin
    perform public.admin_set_driver_approval(p_driver_id, 'approved');
  exception when others then
    -- Identity guard not satisfied: keep `pending`, never break the review.
    return false;
  end;
  return true;
end;
$function$;

revoke execute on function public.driver_auto_approve_if_complete(uuid) from public, anon, authenticated;

-- Hook into the two review RPCs (body text is backed up first).
create table if not exists public.admin_function_backup_20261010 (
  signature text primary key, definition text not null, acl text,
  backed_up_at timestamptz not null default now()
);

do $e4$
declare
  r record; v_def text; v_new text;
begin
  for r in
    select p.oid, p.oid::regprocedure::text sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('admin_driver_kyc_bolivia_manual_review_part', 'admin_upsert_driver_document_v2')
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('E4-20261010' in v_def) > 0 then continue; end if;
    insert into public.admin_function_backup_20261010(signature, definition, acl)
    values ('E4:' || r.sig, v_def, (select proacl::text from pg_proc where oid = r.oid))
    on conflict (signature) do nothing;

    if r.proname = 'admin_upsert_driver_document_v2' then
      v_new := regexp_replace(v_def,
        '(\n\s*)return v_document;',
        E'\\1-- E4-20261010 auto approval\\1v_document := v_document || jsonb_build_object(''driver_auto_approved'', public.driver_auto_approve_if_complete(p_driver_id));\\1return v_document;');
    else
      v_new := regexp_replace(v_def,
        'return\s+jsonb_build_object\(\s*''ok''\s*,\s*true\s*,\s*''document_id''',
        E'-- E4-20261010 auto approval\n  return jsonb_build_object(''driver_auto_approved'', public.driver_auto_approve_if_complete(v_doc.driver_id), ''ok'',true,''document_id''');
    end if;
    if v_new = v_def then
      raise exception 'E4: punto de inserción no encontrado en %', r.sig;
    end if;
    execute v_new;
  end loop;
end
$e4$;
