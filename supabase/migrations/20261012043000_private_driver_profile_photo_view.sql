-- Read-only, scoped access to a verified driver's current onboarding portrait.
-- Driver onboarding stays PRIVATE. Do not copy selfies to a public bucket.
create or replace function public.can_view_driver_profile_photo(
  p_driver_id uuid, p_path text
) returns boolean
language sql stable security definer set search_path=public
as $$
  select auth.uid() is not null and public.is_account_active()
    and p_path is not null
    and p_path like p_driver_id::text||'/%'
    and exists(
      select 1 from public.driver_profiles dp
      where dp.id=p_driver_id and dp.profile_photo_path=p_path
        and (
          dp.id=auth.uid() or public.is_admin()
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
                where t.driver_id=p_driver_id and t.passenger_id=auth.uid()
                  and t.channel=coalesce((
                    select b.environment from public.account_runtime_bindings b
                    where b.user_id=auth.uid()
                  ),'production')
              )
              or exists(
                select 1 from public.driver_offers o
                join public.ride_requests r on r.id=o.ride_request_id
                where o.driver_id=p_driver_id and r.passenger_id=auth.uid()
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
revoke all on function public.can_view_driver_profile_photo(uuid,text)
  from public,anon;
grant execute on function public.can_view_driver_profile_photo(uuid,text)
  to authenticated;

-- An authenticated passenger can sign ONLY a currently associated driver's
-- current portrait object. Existing self/admin policies stay unchanged.
drop policy if exists driver_onboarding_read_authorized_driver_portrait
  on storage.objects;
create policy driver_onboarding_read_authorized_driver_portrait
on storage.objects for select to authenticated
using (
  bucket_id='driver-onboarding'
  and exists(
    select 1 from public.driver_profiles dp
    where dp.profile_photo_path=storage.objects.name
      and public.can_view_driver_profile_photo(dp.id, storage.objects.name)
  )
);

-- Preserve pre-existing viewer permissions, location redaction and payload.
create or replace function public.driver_profile_for_viewer(p_driver_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_allowed boolean:=false;
  v_live boolean:=false;
  v_row public.driver_profiles%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  v_live:=public.can_read_driver_profile(v_uid,p_driver_id);
  v_allowed:=v_live
    or exists(select 1 from public.trips t
              where t.driver_id=p_driver_id and t.passenger_id=v_uid)
    or exists(select 1 from public.delivery_requests d
              where d.courier_id=p_driver_id and d.customer_id=v_uid)
    or exists(select 1 from public.driver_offers o
              join public.ride_requests r on r.id=o.ride_request_id
              where o.driver_id=p_driver_id and r.passenger_id=v_uid);
  if not v_allowed then return null; end if;
  select * into v_row from public.driver_profiles where id=p_driver_id limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'id',v_row.id,'rating',v_row.rating,
    'completed_trips',v_row.completed_trips,
    'vehicle_summary',v_row.vehicle_summary,'city',v_row.city,
    'approval_status',v_row.approval_status,
    'profile_photo_path',case
      when public.can_view_driver_profile_photo(v_row.id,v_row.profile_photo_path)
      then v_row.profile_photo_path else null end,
    'online_status',case when v_live then v_row.online_status else null end,
    'latitude',case when v_live then v_row.latitude else null end,
    'longitude',case when v_live then v_row.longitude else null end,
    'heading_degrees',case when v_live then v_row.heading_degrees else null end,
    'location_updated_at',case when v_live then v_row.location_updated_at else null end
  );
end;
$$;
revoke all on function public.driver_profile_for_viewer(uuid) from public,anon;
grant execute on function public.driver_profile_for_viewer(uuid) to authenticated;
