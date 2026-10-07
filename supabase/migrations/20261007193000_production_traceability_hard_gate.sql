-- Production traceability hard gate + independent Google Play build sequence.
-- Owner-confirmed on 2026-10-07:
--   current Production candidate must use versionCode/build 138;
--   subsequent promoted Production builds advance 139, 140, ...;
--   Preview/internal build numbers never advance the Google Play counter.

alter table public.build_jobs
  add column if not exists source_tree_sha text,
  add column if not exists identity_manifest_sha256 text;

-- Invalidate accidentally generated Production candidates on build 166.
update public.build_jobs
set status = 'cancelled',
    error_message = 'Invalidado: contador Producción corregido a secuencia Google Play 138, 139, 140...',
    completed_at = coalesce(completed_at, now()),
    updated_at = now()
where platform = 'android'
  and artifact_type = 'candidate-apk+aab'
  and build_number = 166
  and status in ('queued','building','ready');

-- Baseline explícito: la próxima Producción debe ser 138.
update public.app_release_gate
set production_store_build_number = 137,
    next_production_build_number = 138,
    production_candidate_build_id = null,
    production_candidate_commit_sha = null,
    production_candidate_version_name = null,
    production_candidate_build_number = null,
    production_candidate_ready_at = null,
    production_candidate_promoted_at = null,
    production_build_id = null,
    production_commit_sha = null,
    production_ready_at = null,
    updated_at = now()
where platform = 'android';

create or replace function public.normalize_android_production_counter()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.platform = 'android'
     and new.production_store_build_number is not null then
    new.next_production_build_number :=
      new.production_store_build_number + 1;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_normalize_android_production_counter
on public.app_release_gate;

create trigger trg_normalize_android_production_counter
before insert or update on public.app_release_gate
for each row execute function public.normalize_android_production_counter();

create or replace function public.enforce_android_store_build_sequence()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_gate public.app_release_gate%rowtype;
  v_expected integer;
begin
  if new.platform <> 'android'
     or new.artifact_type not in ('candidate-apk+aab','apk+aab')
     or new.status not in ('queued','building','ready') then
    return new;
  end if;

  select * into v_gate
  from public.app_release_gate
  where platform = 'android';

  if not found or v_gate.production_store_build_number is null then
    raise exception 'Build Producción bloqueado: falta baseline Google Play';
  end if;

  v_expected := v_gate.production_store_build_number + 1;

  if v_gate.next_production_build_number is distinct from v_expected then
    raise exception
      'Build Producción bloqueado: contador inconsistente; esperado %, recibido %',
      v_expected, v_gate.next_production_build_number;
  end if;

  if new.build_number is distinct from v_expected then
    raise exception
      'Build Producción bloqueado: siguiente versionCode permitido es %',
      v_expected;
  end if;

  if new.artifact_type = 'candidate-apk+aab' then
    if v_gate.preview_commit_sha is null
       or new.commit_sha is distinct from v_gate.preview_commit_sha
       or new.version_name is distinct from v_gate.preview_version_name then
      raise exception
        'Candidato Producción bloqueado: versión/SHA no coincide con Preview vigente';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_enforce_android_store_build_sequence
on public.build_jobs;

create trigger trg_enforce_android_store_build_sequence
before insert or update of platform,artifact_type,version_name,build_number,commit_sha,status
on public.build_jobs
for each row execute function public.enforce_android_store_build_sequence();

create or replace function public.advance_android_store_build_after_promotion()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.platform = 'android'
     and new.artifact_type = 'apk+aab'
     and new.status = 'ready'
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    update public.app_release_gate
    set production_store_build_number = new.build_number,
        next_production_build_number = new.build_number + 1,
        updated_at = now()
    where platform = 'android'
      and production_candidate_build_number = new.build_number
      and production_candidate_commit_sha = new.commit_sha;
  end if;
  return new;
end;
$function$;

drop trigger if exists zz_advance_android_store_build_after_promotion
on public.build_jobs;

create trigger zz_advance_android_store_build_after_promotion
after insert or update of status
on public.build_jobs
for each row execute function public.advance_android_store_build_after_promotion();

revoke all on function public.normalize_android_production_counter()
from public, anon, authenticated;
revoke all on function public.enforce_android_store_build_sequence()
from public, anon, authenticated;
revoke all on function public.advance_android_store_build_after_promotion()
from public, anon, authenticated;
