-- Sincronización de la pista de Prueba interna de Google Play.
-- Alcance: tabla de observaciones de la pista Internal y dos funciones.
-- No cambia la pista de Producción, la tabla android_play_production_sync,
-- app_release_gate, app_releases ni ningún aviso a usuarios.

CREATE TABLE IF NOT EXISTS public.android_play_internal_sync (
  package_name text NOT NULL,
  build_number integer NOT NULL,
  version_name text NOT NULL DEFAULT '',
  release_status text NOT NULL,
  release_name text NOT NULL DEFAULT '',
  matched_build_job_id uuid REFERENCES public.build_jobs(id),
  observed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (package_name, build_number)
);

ALTER TABLE public.android_play_internal_sync ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.android_play_internal_sync FROM anon, authenticated;

-- El worker (service_role) registra lo que Google Play muestra en Prueba interna.
CREATE OR REPLACE FUNCTION public.sync_google_play_internal_releases(p_releases jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_release jsonb;
  v_code text;
  v_count integer := 0;
BEGIN
  IF jsonb_typeof(p_releases) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'La lista de releases internos no es válida';
  END IF;

  FOR v_release IN SELECT * FROM jsonb_array_elements(p_releases) LOOP
    FOR v_code IN SELECT jsonb_array_elements_text(v_release->'version_codes') LOOP
      IF v_code !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'Código de versión inválido en Prueba interna';
      END IF;
      INSERT INTO public.android_play_internal_sync (
        package_name, build_number, version_name, release_status,
        release_name, matched_build_job_id, observed_at
      ) VALUES (
        'com.express.usuario1', v_code::integer,
        coalesce(v_release->>'version_name', ''),
        coalesce(v_release->>'status', ''),
        coalesce(v_release->>'name', ''),
        (SELECT b.id FROM public.build_jobs b
           WHERE b.platform = 'android' AND b.build_number = v_code::integer
             AND b.status = 'ready'
           ORDER BY b.created_at DESC LIMIT 1),
        now()
      )
      ON CONFLICT (package_name, build_number) DO UPDATE SET
        version_name = excluded.version_name,
        release_status = excluded.release_status,
        release_name = excluded.release_name,
        matched_build_job_id = excluded.matched_build_job_id,
        observed_at = now();
      v_count := v_count + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'observed_builds', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_google_play_internal_releases(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_google_play_internal_releases(jsonb) TO service_role;

-- Admin: versión activa en Producción, versión en Prueba interna y última candidata lista.
CREATE OR REPLACE FUNCTION public.admin_play_track_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_internal record;
  v_production record;
  v_candidate record;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT i.build_number, i.version_name, i.release_status, i.release_name,
         i.matched_build_job_id, i.observed_at
    INTO v_internal
    FROM public.android_play_internal_sync i
    ORDER BY i.build_number DESC LIMIT 1;

  SELECT b.build_number, b.version_name, b.status, b.id, b.created_at
    INTO v_candidate
    FROM public.build_jobs b
    WHERE b.platform = 'android' AND b.status = 'ready'
    ORDER BY b.build_number DESC LIMIT 1;

  RETURN jsonb_build_object(
    'internal_build_number', v_internal.build_number,
    'internal_version_name', v_internal.version_name,
    'internal_release_status', v_internal.release_status,
    'internal_observed_at', v_internal.observed_at,
    'internal_matches_candidate', v_internal.matched_build_job_id IS NOT NULL,
    'latest_ready_build_number', v_candidate.build_number,
    'latest_ready_version_name', v_candidate.version_name,
    'latest_ready_build_job_id', v_candidate.id,
    'latest_ready_created_at', v_candidate.created_at,
    'new_build_available_for_internal',
      v_candidate.build_number IS NOT NULL
      AND (v_internal.build_number IS NULL OR v_candidate.build_number > v_internal.build_number)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_play_track_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_play_track_status() TO authenticated;
