-- Include ONLY an actively-authorized driver's private portrait path in
-- passenger offer RPCs. Clients still need private Storage SELECT permission.
-- This removes the extra profile lookup per offer and leaves the bucket PRIVATE.
-- Both functions already scope rows to the authenticated passenger.
CREATE OR REPLACE FUNCTION public.passenger_live_offer_state_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_ride public.ride_requests%rowtype;
  v_offers jsonb:='[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_ride
  from public.ride_requests r
  where r.passenger_id=v_uid
    and r.channel=v_channel
    and r.status in ('searching','offers_received')
    and r.expires_at>now()-interval '30 seconds'
  order by r.created_at desc
  limit 1;

  if v_ride.id is not null then
    select coalesce(
      jsonb_agg(
        to_jsonb(o)||
        jsonb_build_object(
          'driver_profiles',jsonb_build_object(
            'id',dp.id,'rating',dp.rating,
            'completed_trips',dp.completed_trips,
            'vehicle_summary',dp.vehicle_summary,
            'city',dp.city,'approval_status',dp.approval_status,
            'online_status',dp.online_status,
            'profile_photo_path',
              case when public.can_view_driver_profile_photo(
                dp.id,dp.profile_photo_path)
              then dp.profile_photo_path else null end
          ),
          'driver_user',jsonb_build_object(
            'id',u.id,'full_name',u.full_name,'avatar_url',u.avatar_url
          )
        )
        order by o.created_at asc
      ),
      '[]'::jsonb
    )
    into v_offers
    from public.driver_offers o
    left join public.driver_profiles dp on dp.id=o.driver_id
    left join public.users u on u.id=o.driver_id
    where o.ride_request_id=v_ride.id
      and o.channel=v_channel
      and o.status='pending'
      and coalesce(o.expires_at,now()+interval '1 second')>now();
  end if;

  return jsonb_build_object(
    'ride',case when v_ride.id is null then null else to_jsonb(v_ride) end,
    'offers',v_offers,
    'server_now',now()
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.passenger_pending_ride_offers(p_ride_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists (
    select 1
    from public.ride_requests r
    where r.id = p_ride_request_id
      and r.passenger_id = v_uid
  ) then
    raise exception 'Solicitud no disponible';
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(o) ||
      jsonb_build_object(
        'driver_profiles',
        jsonb_build_object(
          'id', dp.id,
          'rating', dp.rating,
          'completed_trips', dp.completed_trips,
          'vehicle_summary', dp.vehicle_summary,
          'city', dp.city,
          'profile_photo_path',
            case when public.can_view_driver_profile_photo(
              dp.id, dp.profile_photo_path)
            then dp.profile_photo_path else null end
        ),
        'driver_user',
        jsonb_build_object(
          'id', u.id,
          'full_name', u.full_name,
          'avatar_url', u.avatar_url
        )
      )
      order by o.created_at asc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.driver_offers o
  left join public.driver_profiles dp on dp.id = o.driver_id
  left join public.users u on u.id = o.driver_id
  where o.ride_request_id = p_ride_request_id
    and o.status = 'pending'
    and coalesce(o.expires_at, now() + interval '1 second') > now();

  return v_result;
end;
$function$
;
