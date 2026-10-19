-- Express Android: configurable update notices from Adminexpress.
-- This migration intentionally creates NO active release or notification.
-- It never promotes an internal-testing AAB into a Production update.

create table if not exists public.app_update_distributions (
  id uuid primary key default gen_random_uuid(),
  build_job_id uuid not null references public.build_jobs(id) on delete restrict,
  channel text not null check (channel in ('production', 'internal')),
  platform text not null default 'android' check (platform = 'android'),
  version_name text not null,
  build_number integer not null check (build_number > 0),
  is_current boolean not null default false,
  is_critical boolean not null default false,
  notes text not null default '',
  play_store_url text not null
    default 'https://play.google.com/store/apps/details?id=com.express.usuario1',
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (build_job_id, channel),
  constraint app_update_distributions_critical_requires_current
    check (not is_critical or is_current),
  constraint app_update_distributions_notes_limit check (char_length(notes) <= 800)
);
create index if not exists app_update_distributions_channel_build_idx
  on public.app_update_distributions(channel, build_number desc);

-- Only SECURITY DEFINER RPCs expose/update settings. No table access for
-- regular users or unauthenticated clients.
alter table public.app_update_distributions enable row level security;
revoke all on public.app_update_distributions from anon, authenticated, public;
grant all on public.app_update_distributions to service_role;

create or replace function public.admin_android_update_distributions()
returns jsonb
language plpgsql security definer
set search_path = public
as $func$
begin
  perform public.admin_assert_environment('production');
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Solo el administrador autorizado puede consultar distribuciones';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(d) order by d.updated_at desc), '[]'::jsonb)
    from public.app_update_distributions d
  );
end;
$func$;

create or replace function public.admin_save_android_update_distribution(
  p_build_id uuid,
  p_channel text,
  p_is_current boolean default false,
  p_is_critical boolean default false,
  p_notes text default '',
  p_play_store_url text default null,
  p_confirmed_in_play boolean default false,
  p_confirmed_critical boolean default false
)
returns jsonb
language plpgsql security definer
set search_path = public
as $func$
declare
  v_job public.build_jobs%rowtype;
  v_distribution_id uuid;
  v_release_id uuid;
  v_production_store_build integer;
  v_notes text := trim(coalesce(p_notes, ''));
  v_url text := coalesce(nullif(trim(p_play_store_url), ''),
    'https://play.google.com/store/apps/details?id=com.express.usuario1');
  v_current boolean := coalesce(p_is_current, false);
  v_critical boolean := coalesce(p_is_critical, false);
  v_confirmed_in_play boolean := coalesce(p_confirmed_in_play, false);
  v_confirmed_critical boolean := coalesce(p_confirmed_critical, false);
begin
  perform public.admin_assert_environment('production');
  if auth.uid() is null or not public.is_admin() then
    raise exception 'No autorizado para gestionar avisos de Express';
  end if;
  if p_channel not in ('production', 'internal') or p_channel is null then
    raise exception 'Canal inválido: solo production o internal';
  end if;
  if v_critical and not v_current then
    raise exception 'Una actualización crítica debe tener activado el aviso de versión actual';
  end if;
  if length(v_notes) > 800 then
    raise exception 'Las notas pueden contener hasta 800 caracteres';
  end if;
  if v_url !~ '^https://play[.]google[.]com/store/apps/details[?]id=com[.]express[.]usuario1(&[^#[:space:]]*)?$' then
    raise exception 'Solo se permite el enlace oficial de Express en Google Play';
  end if;

  select * into v_job
  from public.build_jobs b where b.id = p_build_id for share;
  if not found or v_job.platform <> 'android'
     or v_job.status is distinct from 'ready'
     or v_job.signing_mode is distinct from 'production'
     or v_job.aab_url is null then
    raise exception 'La compilación Android debe estar lista y firmada oficialmente';
  end if;

  if p_channel = 'internal' then
    -- Internal settings are recorded for visibility/history ONLY.
    -- The deployed Android app cannot currently tell Play testers from
    -- Production accounts; never leak internal releases to latest_app_release.
    if v_job.artifact_type not in ('aab','single-app-candidate-apk+aab',
      'apk+aab','candidate-apk+aab') then
      raise exception 'Tipo de compilación no permitido para pruebas internas';
    end if;
  else
    select coalesce(g.production_store_build_number, 0)
    into v_production_store_build
    from public.app_release_gate g where g.platform = 'android';
    if coalesce(v_production_store_build, 0) = 0 then
      raise exception 'Todavía no está verificado el Build de Producción';
    end if;
    if v_current then
      if v_job.build_number <> v_production_store_build then
        raise exception
          'No se puede avisar el Build % a Producción; el Build verificado en Play es %',
          v_job.build_number, v_production_store_build;
      end if;
      if not v_confirmed_in_play then
        raise exception 'Confirma que esta versión está disponible en Play Producción';
      end if;
      if v_job.apk_url is null
         or v_job.artifact_type not in ('apk+aab',
           'single-app-candidate-apk+aab','candidate-apk+aab') then
        raise exception 'Pruebas internas no pueden convertirse en avisos de Producción';
      end if;
      if v_critical and not v_confirmed_critical then
        raise exception 'Debes confirmar por separado el bloqueo de versiones antiguas';
      end if;
      if exists (
        select 1 from public.app_releases r
        where r.platform='android' and r.status='published'
          and r.build_number > v_job.build_number
      ) then
        raise exception 'No se permite anunciar una versión anterior a la publicada';
      end if;
    end if;
  end if;

  insert into public.app_update_distributions (
    build_job_id, channel, version_name, build_number,
    is_current, is_critical, notes, play_store_url, changed_by, updated_at
  ) values (
    v_job.id, p_channel, v_job.version_name, v_job.build_number,
    v_current, v_critical, v_notes, v_url, auth.uid(), now()
  ) on conflict (build_job_id, channel) do update set
    version_name = excluded.version_name,
    build_number = excluded.build_number,
    is_current = excluded.is_current,
    is_critical = excluded.is_critical,
    notes = excluded.notes,
    play_store_url = excluded.play_store_url,
    changed_by = excluded.changed_by,
    updated_at = now()
  returning id into v_distribution_id;

  if p_channel = 'production' then
    if v_current then
      -- Existing AndroidReleaseUpdateGate reads only this Production table.
      -- One verified Production version at a time, never any internal version.
      insert into public.app_releases (
        platform, version_name, build_number,
        apk_url, aab_url, play_store_url, changelog,
        mandatory, status, build_job_id, published_by, published_at, updated_at
      ) values (
        'android', v_job.version_name, v_job.build_number,
        v_job.apk_url, v_job.aab_url, v_url, v_notes,
        v_critical, 'published', v_job.id, auth.uid(), now(), now()
      ) on conflict (platform, build_number) do update set
        version_name = excluded.version_name,
        apk_url = excluded.apk_url,
        aab_url = excluded.aab_url,
        play_store_url = excluded.play_store_url,
        changelog = excluded.changelog,
        mandatory = excluded.mandatory,
        status = 'published',
        build_job_id = excluded.build_job_id,
        published_by = excluded.published_by,
        published_at = now(),
        updated_at = now()
      returning id into v_release_id;
      update public.app_releases
        set status = 'disabled', updated_at = now()
      where platform = 'android' and id <> v_release_id
        and status = 'published';
    else
      -- Disable only the selected build, without silently promoting another.
      update public.app_releases
        set status = 'disabled', updated_at = now()
      where platform = 'android' and build_number = v_job.build_number
        and status = 'published';
    end if;
  end if;

  perform public.admin_log_action('update','app_update_distribution',
    v_distribution_id::text,
    jsonb_build_object(
      'build_job_id',v_job.id,'channel',p_channel,
      'version',v_job.version_name,'build_number',v_job.build_number,
      'is_current',v_current,'is_critical',v_critical
    ));

  return jsonb_build_object(
    'id',v_distribution_id,
    'build_job_id',v_job.id,
    'channel',p_channel,
    'version_name',v_job.version_name,
    'build_number',v_job.build_number,
    'is_current',v_current,'is_critical',v_critical,
    'notes',v_notes,'play_store_url',v_url,
    'in_app_notice_active',p_channel='production' and v_current,
    'internal_notices_require_new_client',p_channel='internal'
  );
end;
$func$;

revoke all on function public.admin_android_update_distributions() from public, anon;
revoke all on function public.admin_save_android_update_distribution(
  uuid, text, boolean, boolean, text, text, boolean, boolean
) from public, anon;
grant execute on function public.admin_android_update_distributions() to authenticated;
grant execute on function public.admin_save_android_update_distribution(
  uuid, text, boolean, boolean, text, text, boolean, boolean
) to authenticated;
