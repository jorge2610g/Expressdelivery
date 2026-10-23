CREATE OR REPLACE FUNCTION public.enforce_driver_offer_deadline()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.created_at := coalesce(new.created_at, now());
  if new.status = 'pending' then
    new.expires_at := new.created_at + interval '15 seconds';
  end if;
  return new;
end;
$function$

