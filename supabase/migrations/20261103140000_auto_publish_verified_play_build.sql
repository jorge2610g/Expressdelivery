-- Publicación automática de la versión verificada en Google Play Producción.
-- Decisión del propietario: cuando la sincronización verifica una build (Play la
-- muestra completada y coincide con la build firmada), esa build pasa a ser la
-- "versión actual" en app_releases y app_update_distributions, sin pasar por el
-- botón del panel. Se conservan los bloqueos (mandatory) ya existentes y no se
-- envía ningún push: el aviso a usuarios sigue siendo una acción manual.

CREATE OR REPLACE FUNCTION public.publish_verified_play_build(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_job public.build_jobs%rowtype;
BEGIN
  IF p_job_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_job FROM public.build_jobs WHERE id = p_job_id;
  IF NOT FOUND OR v_job.platform IS DISTINCT FROM 'android'
     OR v_job.status IS DISTINCT FROM 'ready'
     OR v_job.signing_mode IS DISTINCT FROM 'production'
     OR v_job.apk_url IS NULL OR v_job.aab_url IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.app_releases (
    platform, version_name, build_number, apk_url, aab_url,
    play_store_url, changelog, mandatory, status,
    build_job_id, published_by, published_at, updated_at
  ) VALUES (
    'android', v_job.version_name, v_job.build_number, v_job.apk_url, v_job.aab_url,
    'https://play.google.com/store/apps/details?id=com.express.usuario1', '', false, 'published',
    v_job.id, NULL, now(), now()
  )
  ON CONFLICT (platform, build_number) DO UPDATE SET
    version_name = excluded.version_name,
    apk_url = excluded.apk_url,
    aab_url = excluded.aab_url,
    status = 'published',
    build_job_id = excluded.build_job_id,
    published_at = now(),
    updated_at = now();
    -- mandatory se conserva: si el propietario ya bloqueó esta build, sigue bloqueada.

  UPDATE public.app_releases SET status = 'disabled', updated_at = now()
   WHERE platform = 'android' AND status = 'published'
     AND build_number <> v_job.build_number;

  UPDATE public.app_update_distributions SET is_current = false, is_critical = false, updated_at = now()
   WHERE channel = 'production' AND is_current AND build_job_id <> v_job.id;

  INSERT INTO public.app_update_distributions (
    build_job_id, channel, platform, version_name, build_number,
    is_current, is_critical, notes, changed_by, updated_at
  ) VALUES (
    v_job.id, 'production', 'android', v_job.version_name, v_job.build_number,
    true, false, '', NULL, now()
  )
  ON CONFLICT (build_job_id, channel) DO UPDATE SET
    is_current = true,
    updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.publish_verified_play_build(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.trg_publish_verified_play_build()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.publish_verified_play_build(NEW.production_verified_build_job_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app_release_gate_publish_verified_play_build ON public.app_release_gate;
CREATE TRIGGER app_release_gate_publish_verified_play_build
  AFTER UPDATE OF production_verified_build_job_id ON public.app_release_gate
  FOR EACH ROW
  WHEN (NEW.production_verified_build_job_id IS DISTINCT FROM OLD.production_verified_build_job_id)
  EXECUTE FUNCTION public.trg_publish_verified_play_build();

-- Publicación inmediata de la versión verificada actual (161).
SELECT public.publish_verified_play_build(production_verified_build_job_id)
  FROM public.app_release_gate WHERE platform = 'android';
