-- Express Dual: fixed fare + passenger offer pricing modes.
-- Applied to production Supabase on 2026-09-30.

alter table public.ride_requests
  add column if not exists pricing_mode text not null default 'offer';

alter table public.ride_requests
  drop constraint if exists ride_requests_pricing_mode_check;

alter table public.ride_requests
  add constraint ride_requests_pricing_mode_check
  check (pricing_mode in ('fixed','offer'));

comment on column public.ride_requests.pricing_mode is
  'fixed = precio calculado por Express; offer = tarifa propuesta por el pasajero';
