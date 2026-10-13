-- 2026-10-13 · Express Driver KYC: derive document country from the bound zone
-- Deployed through Supabase migration driver_profile_country_matches_zone_20261013.
-- This script is additive: does not approve accounts or change channel/service flags.
create or replace function public.driver_profile_country_from_zone()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare v_zone_country text;
begin
  if new.zone_id is null then return new; end if;
  select upper(nullif(trim(z.country_code), '')) into v_zone_country
    from public.service_zones z where z.id = new.zone_id;
  if v_zone_country is null then
    raise exception 'Zona del conductor inválida';
  end if;
  new.country_code := v_zone_country;
  return new;
end; $$;

drop trigger if exists trg_driver_profile_country_from_zone on public.driver_profiles;
create trigger trg_driver_profile_country_from_zone
before insert or update of zone_id,country_code on public.driver_profiles
for each row execute function public.driver_profile_country_from_zone();
