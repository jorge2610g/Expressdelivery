CREATE OR REPLACE FUNCTION public.enforce_driver_offer_minimum_lifetime()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'pending' then
    if new.expires_at is null
       or new.expires_at < now() + interval '30 seconds' then
      new.expires_at := now() + interval '30 seconds';
    end if;
  end if;
  return new;
end;
$function$

