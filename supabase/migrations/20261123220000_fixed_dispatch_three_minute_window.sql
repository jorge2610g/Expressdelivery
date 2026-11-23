-- Precio fijo uno a uno: la búsqueda dura 3 minutos (antes 1). Pasados los 3 minutos,
-- el pasajero tiene 30 s para decidir (seguir buscando o cancelar); si no hace nada,
-- el viaje se cancela solo (ya lo hace fixed_dispatch_advance_v1). La solicitud debe
-- seguir vigente durante ventana + decisión, por eso expires_at se extiende a 4 min.

create or replace function public.start_fixed_dispatch()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.dispatch_style = 'sequential' then
    update public.ride_requests
       set dispatch_window_ends_at = now() + interval '180 seconds',
           expires_at = greatest(expires_at, now() + interval '4 minutes')
     where id = new.id;
    perform public.fixed_dispatch_advance_v1(new.id);
  end if;
  return new;
end;
$$;

create or replace function public.passenger_fixed_dispatch_restart_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_ride public.ride_requests%rowtype;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_ride from public.ride_requests
   where id = p_ride_request_id and passenger_id = v_uid for update;
  if not found or v_ride.dispatch_style <> 'sequential' then raise exception 'No autorizado'; end if;
  if v_ride.status not in ('searching','offers_received') then
    raise exception 'Esta solicitud ya no está buscando conductor';
  end if;
  update public.ride_dispatch_attempts set status = 'cancelled', responded_at = now()
   where ride_request_id = v_ride.id and status = 'pending';
  -- Otros 3 minutos de búsqueda. Los conductores que ya recibieron este viaje no se repiten.
  update public.ride_requests
     set dispatch_round = dispatch_round + 1, dispatch_exhausted_at = null,
         dispatch_window_ends_at = now() + interval '180 seconds',
         expires_at = greatest(expires_at, now() + interval '4 minutes'), updated_at = now()
   where id = v_ride.id;
  return public.fixed_dispatch_advance_v1(v_ride.id);
end;
$$;
