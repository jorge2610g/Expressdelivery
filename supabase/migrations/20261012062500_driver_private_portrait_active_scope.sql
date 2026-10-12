-- Tighten signed portrait access to ACTIVE, same-channel passenger relations.
-- A former passenger must not retain permanent access to a driver's current
-- private onboarding portrait after their trip or offer has ended.
create or replace function public.can_view_driver_profile_photo(
  p_driver_id uuid,p_path text
) returns boolean
language sql stable security definer set search_path=public
as $face_scope$
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
            )
          )
        )
    );
$face_scope$;
revoke all on function public.can_view_driver_profile_photo(uuid,text)
  from public,anon;
grant execute on function public.can_view_driver_profile_photo(uuid,text)
  to authenticated;
