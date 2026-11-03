-- Verificación automática de la build que Google Play muestra en Producción.
-- Decisión del propietario: si Play muestra una versión completada y existe la
-- build firmada de producción con el mismo número y versión, esa build queda
-- verificada sin pedir confirmación adicional en el panel.
-- Se conservan: firma de producción, estado listo, enlaces APK y AAB, y el
-- número y versión que deben coincidir. Se elimina solo la exigencia de un
-- registro de QA con hashes, que bloqueaba la verificación automática.
-- No cambia avisos a usuarios, app_releases, bloqueos ni montos.

DO $migration$
DECLARE
  v_sql text;
  v_anchor text := $a$          IF v_qa.qa_verified_at IS NULL
             OR v_qa.qa_source_sha IS DISTINCT FROM v_job.commit_sha
             OR v_qa.qa_tree_sha IS DISTINCT FROM v_job.source_tree_sha
             OR v_qa.qa_apk_sha256 IS DISTINCT FROM v_job.apk_sha256
             OR v_qa.qa_aab_sha256 IS DISTINCT FROM v_job.aab_sha256
             OR v_qa.qa_manifest_sha256 IS DISTINCT FROM v_job.identity_manifest_sha256 THEN
            v_job := NULL;
          END IF;
$a$;
  v_new text := $n$          -- Verificación automática: la build firmada coincide con la que Play muestra.
$n$;
BEGIN
  SELECT pg_get_functiondef('public.sync_google_play_production_releases(jsonb)'::regprocedure)
    INTO v_sql;
  IF strpos(v_sql, 'Verificación automática: la build firmada') > 0 THEN
    RETURN;
  END IF;
  IF (length(v_sql) - length(replace(v_sql, v_anchor, ''))) / length(v_anchor) <> 1 THEN
    RAISE EXCEPTION 'sync_google_play_production_releases has changed: review auto verification before applying';
  END IF;
  EXECUTE replace(v_sql, v_anchor, v_new);
END
$migration$;
