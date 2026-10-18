-- PROPUESTA QA, NO EJECUTADA. NO DESPLEGAR A PRODUCCIÓN.
-- Requiere primero desplegar y validar la función express-push-dispatch del PR #262
-- con canary Preview de UN dispositivo (EXPRESS_OVERLAY_DATA_PUSH=on,
-- EXPRESS_OVERLAY_ALLOWLIST con un único native_push_tokens.id).
-- El receptor Android cierra una barra por ride_request_id mediante
-- type=ride_request_invalidated. El canal Production nunca crea estos eventos.
--
-- No sustituye la publicación Realtime ya existente para ride_requests ni
-- valida el estado de la solicitud al aceptarla: el servidor mantiene autoridad.
CREATE OR REPLACE FUNCTION public.qa_notify_offer_invalidation_preview()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_driver record;
BEGIN
  IF TG_OP <> 'UPDATE'
     OR NEW.channel <> 'preview'
     OR OLD.channel <> 'preview'
     OR OLD.status NOT IN ('searching', 'offers_received')
     OR NEW.status IN ('searching', 'offers_received')
     OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- Avisar SOLO a conductores Preview que recibieron la oferta original,
  -- siguen con overlay activo y tienen verificación reciente de permiso.
  -- No enviar a todos los conductores de la zona.
  FOR v_driver IN
    SELECT DISTINCT n.user_id
    FROM public.notifications n
    WHERE n.channel = 'preview'
      AND n.type = 'ride_request'
      AND n.metadata->>'ride_request_id' = NEW.id::text
      AND n.created_at >= now() - interval '4 minutes'
      AND EXISTS (
        SELECT 1
        FROM public.native_push_tokens t
        WHERE t.user_id = n.user_id
          AND t.channel = 'preview'
          AND t.platform = 'android'
          AND t.active = true
          AND t.floating_offer_enabled = true
          AND t.permission_checked_at > now() - interval '24 hours'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.notifications i
        WHERE i.channel = 'preview'
          AND i.user_id = n.user_id
          AND i.type = 'ride_request_invalidated'
          AND i.metadata->>'ride_request_id' = NEW.id::text
      )
  LOOP
    INSERT INTO public.notifications(user_id, title, body, type, metadata)
    VALUES (
      v_driver.user_id,
      'Express',
      '',
      'ride_request_invalidated',
      jsonb_build_object(
        'ride_request_id', NEW.id,
        'offer_id', NEW.id,
        'channel', 'preview',
        'status', NEW.status
      )
    );
  END LOOP;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS qa_offer_invalidation_preview ON public.ride_requests;
CREATE TRIGGER qa_offer_invalidation_preview
AFTER UPDATE OF status ON public.ride_requests
FOR EACH ROW
EXECUTE FUNCTION public.qa_notify_offer_invalidation_preview();

-- Validación antes de activar:
-- 1. En Preview crear viaje de usuario auditado a conductor auditado.
-- 2. Cancelar: el teléfono canario debe cerrar barra sin heads-up duplicado.
-- 3. Tomado por otro: solo la barra con ese ID debe desaparecer.
-- 4. Sin permisos: se conserva el respaldo de push de NUEVA solicitud.
-- 5. Confirmar cero notificaciones de invalidación en canal Production.
-- Rollback: DROP TRIGGER IF EXISTS qa_offer_invalidation_preview ON public.ride_requests;
--           DROP FUNCTION IF EXISTS public.qa_notify_offer_invalidation_preview();
