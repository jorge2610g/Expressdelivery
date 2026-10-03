
create or replace function public.admin_marketplace_upsert_plus_plan(
  p_id uuid,
  p_zone_id uuid,
  p_name text,
  p_monthly_price numeric,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean,
  p_free_delivery boolean,
  p_included_priority_deliveries integer,
  p_default_discount_percent numeric,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid:=coalesce(p_id,gen_random_uuid());
  v_currency text;
  v_price numeric:=greatest(coalesce(p_monthly_price,0),0);
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select currency_code into v_currency
  from public.service_zones
  where id=p_zone_id;

  if v_currency is null then
    raise exception 'Zona no encontrada';
  end if;

  if coalesce(p_active,false) and v_price<=0 then
    raise exception 'Define un precio mensual mayor a 0 antes de activar Express Plus';
  end if;

  insert into public.marketplace_plus_plans(
    id,zone_id,name,monthly_price,currency_code,
    active,preview_visible,production_visible,
    free_delivery,included_priority_deliveries,
    default_discount_percent,description,updated_at
  )
  values(
    v_id,p_zone_id,
    coalesce(nullif(trim(p_name),''),'Express Plus'),
    v_price,
    v_currency,
    coalesce(p_active,false),
    coalesce(p_preview_visible,true),
    coalesce(p_production_visible,false),
    coalesce(p_free_delivery,true),
    greatest(coalesce(p_included_priority_deliveries,0),0),
    greatest(least(coalesce(p_default_discount_percent,0),100),0),
    nullif(trim(coalesce(p_description,'')),''),
    now()
  )
  on conflict(id) do update set
    zone_id=excluded.zone_id,
    name=excluded.name,
    monthly_price=excluded.monthly_price,
    currency_code=excluded.currency_code,
    active=excluded.active,
    preview_visible=excluded.preview_visible,
    production_visible=excluded.production_visible,
    free_delivery=excluded.free_delivery,
    included_priority_deliveries=excluded.included_priority_deliveries,
    default_discount_percent=excluded.default_discount_percent,
    description=excluded.description,
    updated_at=now();

  return v_id;
end;
$function$;
