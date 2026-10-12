-- Express Android release notices: an audited Google Play registration
-- and a separate, explicitly authorized push announcement.
-- Applying this migration does not publish a release or send any messages.

create or replace function public.admin_register_play_store_release(
  p_build_id uuid,
  p_confirmed_available boolean default false,
  p_mandatory boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_build public.build_jobs%rowtype;
  v_release_id uuid;
  v_store_url constant text :=
    'https://play.google.com/store/apps/details?id=com.express.usuario1';
  v_latest integer;
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_confirmed_available is distinct from true then
    raise exception 'Confirma primero que el mismo versionCode esta disponible en Google Play';
  end if;
  select * into v_build from public.build_jobs where id = p_build_id;
  if not found
     or v_build.platform <> 'android'
     or v_build.artifact_type <> 'apk+aab'
     or v_build.signing_mode <> 'production'
     or v_build.status <> 'ready'
     or v_build.apk_url is null
     or v_build.aab_url is null then
    raise exception 'Se requiere un APK/AAB firmado y promovido de Produccion';
  end if;
  if not exists (
    select 1 from public.android_single_app_candidates c
    where c.promoted_build_id = p_build_id
      and c.qa_verified_at is not null
      and c.approved_at is not null
      and c.promoted_at is not null
  ) then
    raise exception 'Esta compilacion no tiene promocion y QA certificados';
  end if;
  select max(build_number) into v_latest
  from public.app_releases where platform='android' and status='published';
  if v_latest is not null and v_build.build_number <= v_latest then
    raise exception 'No se puede anunciar una version igual o anterior a la publicada';
  end if;

  -- Existing server gate checks administrator, production scope, signing and
  -- archives lower published builds in the same transaction.
  v_release_id := public.admin_publish_build(p_build_id,coalesce(p_mandatory,false));

  update public.app_releases
  set play_store_url = v_store_url, updated_at=now()
  where id=v_release_id;

  perform public.admin_log_action('publish','play_store_release',v_release_id::text,
    jsonb_build_object('build_id',p_build_id,'build_number',v_build.build_number,
      'play_store_url',v_store_url,'mandatory',coalesce(p_mandatory,false),
      'availability_confirmed_by_admin',true));

  return jsonb_build_object('release_id',v_release_id,
    'version_name',v_build.version_name,'build_number',v_build.build_number,
    'play_store_url',v_store_url,'mandatory',coalesce(p_mandatory,false));
end;
$$;

revoke all on function public.admin_register_play_store_release(uuid,boolean,boolean)
from public, anon;
grant execute on function public.admin_register_play_store_release(uuid,boolean,boolean)
to authenticated;

create or replace function public.admin_send_release_update_notice(
  p_audience text default 'all',
  p_zone_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_release public.app_releases%rowtype;
  v_title text;
  v_body text;
  v_result jsonb;
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_audience not in ('all','drivers','passengers') then
    raise exception 'Audiencia invalida';
  end if;
  select * into v_release from public.app_releases
  where platform='android' and status='published'
  order by build_number desc limit 1;
  if not found or v_release.play_store_url is null
      or v_release.play_store_url <>
        'https://play.google.com/store/apps/details?id=com.express.usuario1' then
    raise exception 'No existe una actualizacion aprobada y disponible en Google Play';
  end if;

  v_title:=format('Actualizacion disponible: Express %s',v_release.version_name);
  v_body:=format(
    'Hay una nueva version de Express en Google Play (build %s). Actualiza desde la tienda: %s',
    v_release.build_number,v_release.play_store_url);

  -- Prevent accidental duplicate campaigns for the same version/audience
  -- and scope in a short window, without affecting standard support notices.
  if exists (
    select 1 from public.notification_campaigns n
    where n.channel='production' and n.title=v_title
      and n.audience=p_audience
      and n.zone_id is not distinct from p_zone_id
      and n.created_at > now()-interval '1 hour'
  ) then
    raise exception 'Ya se aviso de esta version a esta audiencia durante la ultima hora';
  end if;

  -- Existing announcement RPC keeps Preview/Production test memberships
  -- isolated, inserts messages in the inbox and queues native/web push.
  v_result := public.admin_send_announcement_v4(
    'production',v_title,v_body,p_audience,p_zone_id,null);
  return v_result || jsonb_build_object(
    'version_name',v_release.version_name,
    'build_number',v_release.build_number,
    'play_store_url',v_release.play_store_url);
end;
$$;

revoke all on function public.admin_send_release_update_notice(text,uuid)
from public, anon;
grant execute on function public.admin_send_release_update_notice(text,uuid)
to authenticated;
