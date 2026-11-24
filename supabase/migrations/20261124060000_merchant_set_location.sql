-- El dueño o encargado de un comercio fija la ubicación predeterminada del local (punto de
-- recogida de «Solicitar repartidor»). Debe quedar dentro de la zona de servicio del comercio.
create or replace function public.marketplace_merchant_set_location(
  p_merchant_id uuid, p_channel text, p_address text, p_latitude numeric, p_longitude numeric)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_role text; v_zone uuid;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  if v_role not in ('owner', 'manager') then
    raise exception 'No tienes permisos para cambiar la ubicación';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'Ubicación no válida';
  end if;
  if length(coalesce(p_address, '')) > 300 then
    raise exception 'La dirección es demasiado larga';
  end if;
  select zone_id into v_zone from public.marketplace_merchants where id = p_merchant_id;
  if v_zone is not null
     and public.service_zone_id_for_point(p_latitude, p_longitude)
         is distinct from v_zone then
    raise exception 'La ubicación debe estar dentro de la zona de servicio de tu local';
  end if;
  update public.marketplace_merchants set
    latitude = p_latitude, longitude = p_longitude,
    address = nullif(trim(coalesce(p_address, '')), ''), updated_at = now()
  where id = p_merchant_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.marketplace_merchant_set_location(uuid, text, text, numeric, numeric) from public, anon;
grant execute on function public.marketplace_merchant_set_location(uuid, text, text, numeric, numeric) to authenticated;
