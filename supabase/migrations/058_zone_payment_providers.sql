-- Payment providers are scoped by active Express service zone.
-- Bolivia uses QR Bolivia (VeriPagos); Chile uses Mercado Pago.

alter table public.service_zones
  add column if not exists payment_provider text,
  add column if not exists payment_enabled boolean not null default true;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='service_zones_payment_provider_check'
      and conrelid='public.service_zones'::regclass
  ) then
    alter table public.service_zones
      add constraint service_zones_payment_provider_check
      check (
        payment_provider is null
        or payment_provider in ('veripagos_qr','mercado_pago')
      );
  end if;
end $$;

update public.service_zones
set payment_provider = case
  when lower(country)='bolivia' then 'veripagos_qr'
  when lower(country)='chile' then 'mercado_pago'
  else payment_provider
end
where payment_provider is null
   or (lower(country)='bolivia' and payment_provider <> 'veripagos_qr')
   or (lower(country)='chile' and payment_provider <> 'mercado_pago');

create or replace function public.admin_set_zone_payment_provider(
  p_zone_id uuid,
  p_provider text,
  p_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_zone public.service_zones%rowtype;
  v_provider text := lower(coalesce(p_provider,''));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select * into v_zone
  from public.service_zones
  where id=p_zone_id;

  if not found then
    raise exception 'Zona no encontrada';
  end if;

  if lower(v_zone.country)='bolivia' and v_provider <> 'veripagos_qr' then
    raise exception 'Bolivia usa únicamente QR Bolivia (VeriPagos)';
  end if;

  if lower(v_zone.country)='chile' and v_provider <> 'mercado_pago' then
    raise exception 'Chile usa únicamente Mercado Pago';
  end if;

  if v_provider not in ('veripagos_qr','mercado_pago') then
    raise exception 'Proveedor no soportado';
  end if;

  update public.service_zones
  set payment_provider=v_provider,
      payment_enabled=coalesce(p_enabled,true),
      updated_at=now()
  where id=p_zone_id
  returning * into v_zone;

  return to_jsonb(v_zone);
end;
$$;

grant execute on function public.admin_set_zone_payment_provider(uuid,text,boolean)
  to authenticated;

create or replace function public.app_zone_context(
  p_lat numeric,
  p_lng numeric,
  p_for text default 'passenger'
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_zone_id uuid;
  v_zone jsonb;
  v_services jsonb := '[]'::jsonb;
  v_subscription jsonb := null;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);

  if v_zone_id is null then
    return jsonb_build_object(
      'inside_coverage',false,
      'zone',null,
      'services','[]'::jsonb,
      'subscription',null,
      'payment',null
    );
  end if;

  select jsonb_build_object(
    'id',z.id,
    'zone_key',z.zone_key,
    'name',z.name,
    'city',z.city,
    'country',z.country,
    'currency_code',z.currency_code,
    'center_latitude',z.center_latitude,
    'center_longitude',z.center_longitude,
    'radius_km',z.radius_km,
    'payment_provider',z.payment_provider,
    'payment_enabled',z.payment_enabled
  )
  into v_zone
  from public.service_zones z
  where z.id=v_zone_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'service_key',s.service_key,
        'name',s.name,
        'description',s.description,
        'icon_key',s.icon_key,
        'vehicle_type',coalesce(s.vehicle_type,'car'),
        'enabled',zs.enabled,
        'passenger_visible',zs.passenger_visible,
        'driver_visible',zs.driver_visible,
        'allow_bidding',zs.allow_bidding,
        'allow_fixed_price',zs.allow_fixed_price,
        'scheduled_enabled',zs.scheduled_enabled,
        'sort_order',zs.sort_order,
        'fare_rule',public.effective_fare_rule(s.service_key,v_zone_id)
      )
      order by zs.sort_order,s.name
    ),
    '[]'::jsonb
  )
  into v_services
  from public.zone_service_catalog zs
  join public.service_catalog s on s.service_key=zs.service_key
  where zs.zone_id=v_zone_id
    and zs.enabled=true
    and case
      when lower(coalesce(p_for,'passenger'))='driver' then zs.driver_visible
      else zs.passenger_visible
    end;

  select jsonb_build_object(
    'enabled',coalesce(zs.enabled,false),
    'enforce_access',coalesce(zs.enforce_access,false),
    'provider',coalesce(gs.provider,'veripagos'),
    'provider_enabled',coalesce(gs.provider_enabled,false),
    'qr_validity',coalesce(gs.qr_validity,'0/00:15')
  )
  into v_subscription
  from public.driver_subscription_zone_settings zs
  left join public.driver_subscription_settings gs on gs.id=true
  where zs.zone_id=v_zone_id;

  return jsonb_build_object(
    'inside_coverage',true,
    'zone',v_zone,
    'services',coalesce(v_services,'[]'::jsonb),
    'subscription',v_subscription,
    'payment',jsonb_build_object(
      'provider',v_zone->>'payment_provider',
      'enabled',coalesce((v_zone->>'payment_enabled')::boolean,false),
      'method',case
        when v_zone->>'payment_provider'='veripagos_qr' then 'pagorut'
        when v_zone->>'payment_provider'='mercado_pago' then 'mercado_pago'
        else null
      end,
      'label',case
        when v_zone->>'payment_provider'='veripagos_qr' then 'QR Bolivia'
        when v_zone->>'payment_provider'='mercado_pago' then 'Mercado Pago'
        else null
      end
    )
  );
end;
$$;
