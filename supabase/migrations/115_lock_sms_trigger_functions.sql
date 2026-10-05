-- Trigger functions execute through triggers; no API role needs direct EXECUTE.

revoke all on function public.enforce_passenger_phone_verification()
from public,anon,authenticated;

revoke all on function public.enforce_driver_phone_verification_offer()
from public,anon,authenticated;

revoke all on function public.enforce_driver_phone_verification_online()
from public,anon,authenticated;
