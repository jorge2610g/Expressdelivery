-- Scope identity verification reads to the admin-selected country and zone.
-- Keeps the legacy RPC untouched so older clients continue to work.
-- 2026-10-07

create or replace function public.admin_identity_verification_list_scoped(
  p_limit integer default 200,
  p_country_code text default null,
  p_zone_id uuid default null,
  p_provider text default null,
  p_provider_environment text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        v.*,
        u.full_name,
        u.phone,
        u.avatar_url,
        coalesce(dp.zone_id, u.last_zone_id) as scope_zone_id,
        sz.name as scope_zone_name,
        sz.zone_key as scope_zone_key,
        sz.country_code as scope_country_code,
        sz.country as scope_country
      from public.identity_verifications v
      left join public.users u
        on u.id = v.user_id
      left join public.driver_profiles dp
        on dp.id = v.user_id
      left join public.service_zones sz
        on sz.id = coalesce(dp.zone_id, u.last_zone_id)
      where
        (
          p_zone_id is null
          or coalesce(dp.zone_id, u.last_zone_id) = p_zone_id
        )
        and (
          p_country_code is null
          or upper(coalesce(sz.country_code, '')) = upper(p_country_code)
        )
        and (
          p_provider is null
          or lower(coalesce(v.provider, '')) = lower(p_provider)
        )
        and (
          p_provider_environment is null
          or lower(coalesce(v.provider_environment, '')) =
             lower(p_provider_environment)
        )
      order by v.created_at desc
      limit least(greatest(coalesce(p_limit, 200), 1), 500)
    ) x
  );
end;
$$;

revoke all on function public.admin_identity_verification_list_scoped(
  integer, text, uuid, text, text
) from public, anon;

grant execute on function public.admin_identity_verification_list_scoped(
  integer, text, uuid, text, text
) to authenticated, service_role;

comment on function public.admin_identity_verification_list_scoped(
  integer, text, uuid, text, text
) is
  'Admin identity list scoped by the user/driver operational zone. Verification document country is returned but is not used as the operational zone filter.';
