-- Admin-confirmed deletion for a single scoped advertising banner.
-- Related aggregate events are removed through the existing FK cascade.
begin;

create or replace function public.admin_landing_banner_delete_v1(
  p_id uuid,
  p_zone_id uuid,
  p_channel text
) returns boolean
language plpgsql security definer set search_path=public as $$
declare
  v_ctx jsonb;
  v_country text;
begin
  v_ctx:=public.admin_access_context();
  if v_ctx->>'allowed' is distinct from 'true'
      or v_ctx->>'read_only'='true'
      or p_id is null or p_zone_id is null
      or p_channel is null or p_channel not in ('preview','production')
      or not public.admin_environment_allowed(p_channel) then
    raise exception 'No autorizado para eliminar publicidad';
  end if;

  select country_code into v_country
  from public.service_zones where id=p_zone_id;
  if not found then raise exception 'Zona no encontrada'; end if;
  if v_ctx->>'zone_id' is not null
      and v_ctx->>'zone_id' <> p_zone_id::text then
    raise exception 'Zona fuera de tus permisos';
  end if;
  if v_ctx->>'country_code' is not null
      and v_ctx->>'country_code' <> v_country then
    raise exception 'País fuera de tus permisos';
  end if;

  delete from public.passenger_landing_banners
  where id=p_id and zone_id=p_zone_id and channel=p_channel;
  if not found then raise exception 'El banner no pertenece a la zona y entorno'; end if;
  return true;
end;
$$;

revoke all on function public.admin_landing_banner_delete_v1(uuid,uuid,text)
  from public,anon;
grant execute on function public.admin_landing_banner_delete_v1(uuid,uuid,text)
  to authenticated;

commit;
