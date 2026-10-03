-- Store Mercado Pago credentials server-side by Chile service zone.
-- Never expose access_token to authenticated clients or Flutter/web code.

create table if not exists private.zone_payment_provider_settings (
  zone_id uuid primary key references public.service_zones(id) on delete cascade,
  provider text not null check (provider in ('mercado_pago')),
  public_key text,
  access_token text,
  extra_config jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

revoke all on table private.zone_payment_provider_settings
  from public, anon, authenticated;

create or replace function public.service_get_zone_payment_provider_settings(
  p_zone_id uuid
)
returns jsonb
language sql
security definer
set search_path='public','private'
as $$
  select case
    when s.zone_id is null then null
    else jsonb_build_object(
      'zone_id',s.zone_id,
      'provider',s.provider,
      'public_key',s.public_key,
      'access_token',s.access_token,
      'extra_config',s.extra_config,
      'updated_at',s.updated_at
    )
  end
  from (select p_zone_id as requested_zone) x
  left join private.zone_payment_provider_settings s
    on s.zone_id=x.requested_zone;
$$;

create or replace function public.service_set_zone_payment_provider_settings(
  p_zone_id uuid,
  p_provider text,
  p_public_key text,
  p_access_token text,
  p_extra_config jsonb default '{}'::jsonb,
  p_updated_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='public','private'
as $$
declare
  v_zone public.service_zones%rowtype;
  v_row private.zone_payment_provider_settings%rowtype;
begin
  select * into v_zone
  from public.service_zones
  where id=p_zone_id;

  if not found then
    raise exception 'Zona no encontrada';
  end if;

  if lower(v_zone.country) <> 'chile' then
    raise exception 'Mercado Pago solo está habilitado para zonas de Chile';
  end if;

  if lower(coalesce(p_provider,'')) <> 'mercado_pago' then
    raise exception 'Proveedor no soportado';
  end if;

  insert into private.zone_payment_provider_settings(
    zone_id,provider,public_key,access_token,extra_config,updated_by,updated_at
  )
  values(
    p_zone_id,
    'mercado_pago',
    nullif(trim(coalesce(p_public_key,'')),''),
    nullif(trim(coalesce(p_access_token,'')),''),
    coalesce(p_extra_config,'{}'::jsonb),
    p_updated_by,
    now()
  )
  on conflict(zone_id) do update set
    provider=excluded.provider,
    public_key=coalesce(
      excluded.public_key,
      private.zone_payment_provider_settings.public_key
    ),
    access_token=coalesce(
      excluded.access_token,
      private.zone_payment_provider_settings.access_token
    ),
    extra_config=coalesce(
      excluded.extra_config,
      private.zone_payment_provider_settings.extra_config
    ),
    updated_by=excluded.updated_by,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'zone_id',v_row.zone_id,
    'provider',v_row.provider,
    'public_key',v_row.public_key,
    'access_token',v_row.access_token,
    'extra_config',v_row.extra_config,
    'updated_at',v_row.updated_at
  );
end;
$$;

revoke all on function public.service_get_zone_payment_provider_settings(uuid)
  from public, anon, authenticated;
revoke all on function public.service_set_zone_payment_provider_settings(
  uuid,text,text,text,jsonb,uuid
) from public, anon, authenticated;

grant execute on function public.service_get_zone_payment_provider_settings(uuid)
  to service_role;
grant execute on function public.service_set_zone_payment_provider_settings(
  uuid,text,text,text,jsonb,uuid
) to service_role;
