-- Only a promoted and signed Production APK+AAB may become an app release.
-- Preview and unapproved single-app candidate binaries cannot be published.
CREATE OR REPLACE FUNCTION public.admin_publish_build(
  p_build_id uuid, p_mandatory boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $body$
DECLARE v_build public.build_jobs%rowtype; v_release_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_build FROM public.build_jobs WHERE id=p_build_id;
  IF NOT FOUND OR v_build.platform <> 'android' OR v_build.artifact_type <> 'apk+aab' THEN
    RAISE EXCEPTION 'Solo se publican APK/AAB promocionados de Producción';
  END IF;
  IF v_build.status <> 'ready' OR v_build.signing_mode <> 'production'
     OR v_build.apk_url IS NULL OR v_build.aab_url IS NULL THEN
    RAISE EXCEPTION 'Falta firma de Producción o artefactos listos';
  END IF;
  INSERT INTO public.app_releases(
    platform,version_name,build_number,apk_url,aab_url,changelog,
    mandatory,status,build_job_id,published_by,published_at,updated_at
  ) VALUES (
    'android',v_build.version_name,v_build.build_number,v_build.apk_url,
    v_build.aab_url,v_build.changelog,coalesce(p_mandatory,false),
    'published',v_build.id,auth.uid(),now(),now()
  )
  ON CONFLICT(platform,build_number) DO UPDATE SET
    version_name=excluded.version_name,apk_url=excluded.apk_url,
    aab_url=excluded.aab_url,changelog=excluded.changelog,
    mandatory=excluded.mandatory,status='published',
    build_job_id=excluded.build_job_id,published_by=excluded.published_by,
    published_at=now(),updated_at=now()
  RETURNING id INTO v_release_id;
  UPDATE public.app_releases SET status='disabled',updated_at=now()
  WHERE platform='android' AND id<>v_release_id
    AND status='published' AND build_number<v_build.build_number;
  PERFORM public.admin_log_action('publish','app_release',v_release_id::text,
    jsonb_build_object('build_job_id',v_build.id,'version_name',v_build.version_name,
      'build_number',v_build.build_number,'mandatory',coalesce(p_mandatory,false)));
  RETURN v_release_id;
END; $body$;
REVOKE ALL ON FUNCTION public.admin_publish_build(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_publish_build(uuid,boolean) TO authenticated;
