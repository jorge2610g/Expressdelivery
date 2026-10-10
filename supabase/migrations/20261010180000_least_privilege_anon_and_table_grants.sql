-- E6 · 2026-10-10 · Mínimo privilegio (defensa en profundidad).
-- No cambia el comportamiento efectivo actual:
--  * Ninguna política RLS permite escribir a anon/public (verificado), así que
--    los GRANT INSERT/UPDATE/DELETE de anon sobre 33 tablas no se usaban.
--  * TRUNCATE/TRIGGER/REFERENCES no se exponen por PostgREST; la app no los usa.
--  * Las funciones revocadas a anon exigen sesión (auth.uid() / is_admin) o son
--    funciones de trigger; las públicas previas al login se mantienen.
-- Rollback: docs/backups/20261010_E6_rollback.sql

-- 0. Respaldo exacto de ACL (tablas y funciones) para rollback.
create table if not exists public.acl_backup_20261010_e6 (
  kind text not null, object text not null, acl text,
  backed_up_at timestamptz not null default now(),
  primary key (kind, object)
);
alter table public.acl_backup_20261010_e6 enable row level security;
revoke all on public.acl_backup_20261010_e6 from public, anon, authenticated;
insert into public.acl_backup_20261010_e6(kind, object, acl)
select 'table', c.oid::regclass::text, c.relacl::text
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p','v','m')
on conflict do nothing;
insert into public.acl_backup_20261010_e6(kind, object, acl)
select 'function', p.oid::regprocedure::text, p.proacl::text
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
on conflict do nothing;

-- 1. Tablas: anon no escribe; nadie del cliente trunca ni crea triggers/FKs.
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public from anon;
revoke truncate, references, trigger
  on all tables in schema public from authenticated;

-- 2. Funciones SECURITY DEFINER que no deben ejecutarse sin sesión.
do $e6$
declare
  v_sig text;
  v_anon_revoke text[] := array[
    'public.admin_driver_detail_v2(uuid,text)',
    'public.admin_resolve_emergency_v2(uuid,text)',
    'public.admin_set_account_status_v2(uuid,text,text)',
    'public.admin_set_driver_approval_v2(uuid,text,text)',
    'public.admin_trip_detail_v2(uuid,text)',
    'public.admin_update_driver_profile_v2(uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer,text)',
    'public.admin_update_user_profile_v2(uuid,text,text,text,text,uuid,text)',
    'public.admin_upsert_driver_document_v2(uuid,uuid,text,text,text,text,timestamp with time zone,text,text)',
    'public.admin_user_detail_v2(uuid,text)',
    'public.request_my_driver_zone_change(uuid)',
    'public.update_my_driver_documents_for_review(jsonb)',
    'public.update_my_driver_profile_photo_for_review(text)',
    'public.update_my_driver_vehicle_for_review(text,text,text,text,text,integer,text[])'
  ];
  v_all_revoke text[] := array[
    -- trigger functions: never callable as RPC
    'public.driver_kyc_bolivia_face_profile_mirror()',
    'public.driver_kyc_bolivia_part_states()',
    'public.driver_kyc_bolivia_profile_part_sync()',
    -- per-driver stats; only used inside SECURITY DEFINER functions
    'public.driver_priority_summary_for_v2(uuid,text)'
  ];
begin
  foreach v_sig in array v_anon_revoke loop
    if to_regprocedure(v_sig) is not null then
      execute format('revoke execute on function %s from public, anon', v_sig);
      execute format('grant execute on function %s to authenticated', v_sig);
    end if;
  end loop;
  foreach v_sig in array v_all_revoke loop
    if to_regprocedure(v_sig) is not null then
      execute format('revoke execute on function %s from public, anon, authenticated', v_sig);
    end if;
  end loop;
end
$e6$;
