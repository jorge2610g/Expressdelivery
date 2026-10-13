-- Express Web: Taxi and Envíos are modes of one ride pipeline.
-- No production zone or commerce delivery is enabled by this migration.
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS service_mode text NOT NULL DEFAULT 'taxi',
  ADD COLUMN IF NOT EXISTS parcel_sender_name text,
  ADD COLUMN IF NOT EXISTS parcel_sender_phone text,
  ADD COLUMN IF NOT EXISTS parcel_recipient_name text,
  ADD COLUMN IF NOT EXISTS parcel_recipient_phone text,
  ADD COLUMN IF NOT EXISTS parcel_details text,
  ADD COLUMN IF NOT EXISTS parcel_photo_paths text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.ride_requests
  DROP CONSTRAINT IF EXISTS ride_requests_service_mode_check;
ALTER TABLE public.ride_requests
  ADD CONSTRAINT ride_requests_service_mode_check
  CHECK (service_mode IN ('taxi','parcel'));

INSERT INTO public.service_catalog(service_key,name,description,icon_key,
 vehicle_type,enabled,allow_bidding,allow_fixed_price,sort_order,
 passenger_visible,driver_visible,scheduled_enabled)
VALUES('parcel','Envíos','Modalidad dentro del flujo de Taxi','package',
 'none',true,true,false,48,true,true,false)
ON CONFLICT(service_key) DO NOTHING;

INSERT INTO public.zone_service_catalog(
 zone_id,service_key,enabled,passenger_visible,driver_visible,
 allow_bidding,allow_fixed_price,scheduled_enabled,sort_order)
SELECT id,'parcel',false,false,false,true,false,false,48
FROM public.service_zones
ON CONFLICT(zone_id,service_key) DO NOTHING;

-- Explicit Preview enablement in the isolated Iquique test zone.
INSERT INTO public.admin_environment_config(
 environment,module,record_key,payload)
SELECT 'preview','zone_services',id::text||':parcel',
 jsonb_build_object('name','Envíos','zone_id',id,'service_key','parcel',
 'enabled',true,'passenger_visible',true,'driver_visible',true,
 'vehicle_type','none','sort_order',48,'allow_bidding',true,
 'allow_fixed_price',false,'scheduled_enabled',false)
FROM public.service_zones WHERE zone_key='iquique'
ON CONFLICT(environment,module,record_key)
DO UPDATE SET payload=EXCLUDED.payload,updated_at=now();

CREATE OR REPLACE FUNCTION public.express_parcel_zone_available(
 p_zone_id uuid,p_channel text,p_audience text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public AS $$
 SELECT EXISTS(
  SELECT 1 FROM public.zone_service_catalog zc
  JOIN public.service_catalog c ON c.service_key=zc.service_key
  LEFT JOIN public.admin_environment_config a
   ON p_channel='preview' AND a.environment='preview'
   AND a.module='zone_services'
   AND a.record_key=zc.zone_id::text||':parcel'
  WHERE zc.zone_id=p_zone_id AND zc.service_key='parcel' AND c.enabled
   AND CASE WHEN p_channel='preview'
      THEN coalesce((a.payload->>'enabled')::boolean,false)
      ELSE zc.enabled END
   AND CASE WHEN p_audience='driver'
      THEN CASE WHEN p_channel='preview'
         THEN coalesce((a.payload->>'driver_visible')::boolean,false)
         ELSE zc.driver_visible END
      ELSE CASE WHEN p_channel='preview'
         THEN coalesce((a.payload->>'passenger_visible')::boolean,false)
         ELSE zc.passenger_visible END END);
$$;

CREATE OR REPLACE FUNCTION public.guard_ride_request_parcel_mode()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public AS $$
DECLARE v_zone uuid;
BEGIN
 IF new.service_mode='taxi' THEN RETURN new; END IF;
 IF new.pickup_latitude IS NULL OR new.pickup_longitude IS NULL THEN
  RAISE EXCEPTION 'Envíos requiere una dirección de recogida';
 END IF;
 v_zone:=public.service_zone_id_for_point(
   new.pickup_latitude,new.pickup_longitude);
 IF v_zone IS NULL OR NOT public.express_parcel_zone_available(
   v_zone,new.channel,'passenger') THEN
   RAISE EXCEPTION 'Envíos no habilitado en esta zona y entorno';
 END IF;
 IF new.scheduled_for IS NOT NULL THEN
  RAISE EXCEPTION 'La programación de Envíos aún no está disponible';
 END IF;
 IF nullif(trim(new.parcel_sender_name),'') IS NULL OR
    nullif(trim(new.parcel_sender_phone),'') IS NULL OR
    nullif(trim(new.parcel_recipient_name),'') IS NULL OR
    nullif(trim(new.parcel_recipient_phone),'') IS NULL THEN
  RAISE EXCEPTION 'Completa el remitente y destinatario';
 END IF;
 IF coalesce(cardinality(new.parcel_photo_paths),0)>4 OR EXISTS(
   SELECT 1 FROM unnest(new.parcel_photo_paths) p
   WHERE p NOT LIKE (new.passenger_id::text||'/parcel/%')) THEN
   RAISE EXCEPTION 'Fotos de paquete inválidas';
 END IF;
 RETURN new;
END $$;
DROP TRIGGER IF EXISTS guard_ride_request_parcel_mode
 ON public.ride_requests;
CREATE TRIGGER guard_ride_request_parcel_mode
BEFORE INSERT OR UPDATE OF service_mode,parcel_sender_name,
 parcel_sender_phone,parcel_recipient_name,parcel_recipient_phone,
 parcel_photo_paths,scheduled_for,channel,pickup_latitude,pickup_longitude
ON public.ride_requests
FOR EACH ROW EXECUTE FUNCTION public.guard_ride_request_parcel_mode();

CREATE OR REPLACE FUNCTION public.guard_parcel_ride_offer_permission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public AS $$
DECLARE v_mode text;v_zone uuid;
BEGIN
 SELECT r.service_mode,r.zone_id INTO v_mode,v_zone
 FROM public.ride_requests r WHERE r.id=new.ride_request_id;
 IF v_mode='parcel' AND (
   NOT public.driver_work_permission_allowed(
     new.driver_id,'parcel',new.channel)
   OR NOT public.express_parcel_zone_available(
     v_zone,new.channel,'driver')) THEN
   RAISE EXCEPTION 'No tienes autorización de Envíos';
 END IF;
 RETURN new;
END $$;
DROP TRIGGER IF EXISTS guard_parcel_ride_offer_permission
ON public.driver_offers;
CREATE TRIGGER guard_parcel_ride_offer_permission
BEFORE INSERT OR UPDATE OF driver_id,ride_request_id,channel
ON public.driver_offers FOR EACH ROW
EXECUTE FUNCTION public.guard_parcel_ride_offer_permission();

-- Selection is performed by the passenger: read the approved driver grant
-- directly rather than calling an RPC that only authorizes a driver session.
CREATE OR REPLACE FUNCTION public.guard_parcel_trip_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public AS $$
DECLARE v_mode text;v_zone uuid;v_channel text;v_driver_zone uuid;
BEGIN
 SELECT r.service_mode,r.zone_id,r.channel
   INTO v_mode,v_zone,v_channel
   FROM public.ride_requests r WHERE r.id=new.ride_request_id;
 IF v_mode='parcel' THEN
  SELECT dp.zone_id INTO v_driver_zone
   FROM public.driver_profiles dp WHERE dp.id=new.driver_id;
  IF v_driver_zone IS DISTINCT FROM v_zone OR NOT EXISTS(
     SELECT 1 FROM public.driver_work_permissions p
     WHERE p.driver_id=new.driver_id AND p.channel=v_channel
       AND p.zone_id=v_driver_zone AND p.service_key='parcel'
       AND p.status='approved'
   ) OR public.admin_user_runtime_environment(new.driver_id)<>v_channel
   OR NOT public.express_parcel_zone_available(
     v_zone,v_channel,'driver') THEN
   RAISE EXCEPTION 'El conductor ya no está autorizado para Envíos';
  END IF;
 END IF;
 RETURN new;
END $$;
DROP TRIGGER IF EXISTS guard_parcel_trip_assignment ON public.trips;
CREATE TRIGGER guard_parcel_trip_assignment
BEFORE INSERT OR UPDATE OF ride_request_id,driver_id
ON public.trips FOR EACH ROW
EXECUTE FUNCTION public.guard_parcel_trip_assignment();

-- Canonical Taxi eligibility, distance, priority and expiry logic preserved;
-- parcel requests are filtered by their own approval before dispatch.

CREATE OR REPLACE FUNCTION public.available_ride_requests_for_driver()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_lat numeric;
  v_lng numeric;
  v_zone_id uuid;
  v_audit boolean := false;
  v_limit integer := 20;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not (
    public.driver_work_permission_allowed(v_uid,'ride',public.admin_user_runtime_environment(v_uid))
    or public.driver_work_permission_allowed(v_uid,'parcel',public.admin_user_runtime_environment(v_uid))
  ) then return '[]'::jsonb; end if;
  if not public.is_approved_online_driver(v_uid) then
    return '[]'::jsonb;
  end if;

  select
    coalesce(scheduled_publish_before_minutes,30),
    coalesce(request_visible_seconds,180),
    coalesce(max_visible_requests_driver,20),
    coalesce(max_driver_request_radius_km,15)
  into v_scheduled_before,v_visible_seconds,v_max_visible,v_radius
  from public.app_settings where id=true;

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;

  v_limit := case
    when v_audit then 250
    else least(greatest(v_max_visible,1),100)
  end;

  select latitude,longitude,zone_id
    into v_lat,v_lng,v_zone_id
  from public.driver_profiles
  where id=v_uid
  limit 1;

  if v_zone_id is null
     or not public.driver_subscription_allows_dispatch(v_uid) then
    return '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.created_at asc),
    '[]'::jsonb
  )
  into v_result
  from (
    select r.*
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and r.zone_id = v_zone_id
      and public.same_operational_scope(r.passenger_id,v_uid)
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now()+make_interval(
            mins=>least(greatest(v_scheduled_before,5),1440)
          )
      )
      and (
        r.scheduled_for is not null
        or r.created_at >
          now()-make_interval(
            secs=>least(greatest(v_visible_seconds,30),1800)
          )
      )
      and exists(
        select 1
        from public.zone_service_catalog zs
        where zs.zone_id=v_zone_id
          and zs.service_key=r.category
          and zs.enabled=true
          and zs.driver_visible=true
      )
      and case when r.service_mode='parcel' then
        public.driver_work_permission_allowed(
          v_uid,'parcel',public.admin_user_runtime_environment(v_uid))
        and public.express_parcel_zone_available(v_zone_id,r.channel,'driver')
      else
        public.driver_work_permission_allowed(
          v_uid,'ride',public.admin_user_runtime_environment(v_uid))
      end
      and (
        v_lat is null
        or v_lng is null
        or r.pickup_latitude is null
        or r.pickup_longitude is null
        or public.geo_distance_km(
          v_lat,v_lng,r.pickup_latitude,r.pickup_longitude
        ) <= least(greatest(v_radius,1),100)
      )
    order by r.created_at asc
    limit v_limit
  ) x;

  return v_result;
end;
$function$

