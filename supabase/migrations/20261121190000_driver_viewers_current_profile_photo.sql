-- La fila "X conductores están viendo tu solicitud" mostraba la foto antigua
-- (users.avatar_url) y no la foto de perfil actual del conductor que sí se ve
-- en sus ofertas. Se entrega la ruta de la foto de perfil solo si el pasajero
-- puede verla, y se permite ver la foto de un conductor aprobado que está
-- viendo su solicitud en búsqueda, además de ofertas y viajes activos.

create or replace function public.can_view_driver_profile_photo(p_driver_id uuid, p_path text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select auth.uid() is not null and public.is_account_active()
    and p_path is not null
    and p_path like p_driver_id::text||'/%'
    and exists(
      select 1 from public.driver_profiles dp
      where dp.id=p_driver_id and dp.profile_photo_path=p_path
        and (
          dp.id=auth.uid()
          or public.is_admin()
          or (
            dp.approval_status='approved'
            and coalesce((
              select b.environment from public.account_runtime_bindings b
              where b.user_id=auth.uid()
            ),'production')=
            coalesce((
              select b.environment from public.account_runtime_bindings b
              where b.user_id=p_driver_id
            ),'production')
            and (
              exists(
                select 1 from public.trips t
                where t.driver_id=p_driver_id
                  and t.passenger_id=auth.uid()
                  and t.status not in ('completed','cancelled')
                  and t.channel=coalesce((
                    select b.environment from public.account_runtime_bindings b
                    where b.user_id=auth.uid()
                  ),'production')
              )
              or exists(
                select 1 from public.driver_offers o
                join public.ride_requests r on r.id=o.ride_request_id
                where o.driver_id=p_driver_id
                  and r.passenger_id=auth.uid()
                  and o.status in ('pending','selected')
                  and r.status in ('searching','offers_received','driver_selected')
                  and (o.expires_at is null or o.expires_at>now())
                  and r.channel=o.channel
                  and r.channel=coalesce((
                    select b.environment from public.account_runtime_bindings b
                    where b.user_id=auth.uid()
                  ),'production')
              )
              or exists(
                select 1 from public.ride_request_views v
                join public.ride_requests r on r.id=v.ride_request_id
                where v.driver_id=p_driver_id
                  and r.passenger_id=auth.uid()
                  and r.status in ('searching','offers_received')
                  and (r.expires_at is null or r.expires_at>now())
                  and r.channel=coalesce((
                    select b.environment from public.account_runtime_bindings b
                    where b.user_id=auth.uid()
                  ),'production')
              )
            )
          )
        )
    );
$$;

create or replace function public.ride_request_viewers(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists (
    select 1
    from public.ride_requests r
    where r.id = p_ride_request_id
      and r.passenger_id = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'driver_id', v.driver_id,
        'viewed_at', v.viewed_at,
        'full_name', u.full_name,
        'avatar_url', u.avatar_url,
        'profile_photo_path',
          case when public.can_view_driver_profile_photo(v.driver_id, dp.profile_photo_path)
               then dp.profile_photo_path else null end,
        'rating', dp.rating,
        'completed_trips', dp.completed_trips,
        'vehicle_summary', dp.vehicle_summary
      )
      order by v.viewed_at desc
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select rv.driver_id, rv.viewed_at
    from public.ride_request_views rv
    where rv.ride_request_id = p_ride_request_id
    order by rv.viewed_at desc
    limit 12
  ) v
  join public.users u on u.id = v.driver_id
  left join public.driver_profiles dp on dp.id = v.driver_id;

  return v_result;
end;
$$;
