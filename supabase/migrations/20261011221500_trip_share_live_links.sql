-- Secure live trip sharing for passengers.
-- The raw token is returned once to the authenticated passenger and is never stored.
-- Public viewers can only read a deliberately minimal projection while the trip is active.

create table if not exists public.trip_share_links (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  passenger_id uuid not null references public.users(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours'),
  revoked_at timestamptz
);

create index if not exists trip_share_links_trip_active_idx
  on public.trip_share_links (trip_id, channel, expires_at desc)
  where revoked_at is null;

create index if not exists trip_share_links_passenger_idx
  on public.trip_share_links (passenger_id, created_at desc);

alter table public.trip_share_links enable row level security;

revoke all on table public.trip_share_links from public, anon, authenticated;
grant select, insert, update, delete on table public.trip_share_links to service_role;

create or replace function public.create_trip_share_link(
  p_trip_id uuid,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_status text;
  v_access jsonb;
  v_token text;
  v_hash text;
  v_expires_at timestamptz := now() + interval '12 hours';
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;

  if v_channel not in ('preview','production') then
    raise exception 'Canal inválido';
  end if;

  v_access := public.ensure_current_runtime_access(v_channel);
  if coalesce((v_access->>'allowed')::boolean, false) is not true then
    raise exception 'Cuenta sin acceso al entorno solicitado';
  end if;

  if not exists (
    select 1
    from public.app_settings s
    where s.id = true
      and coalesce(s.share_trip_enabled, true) = true
  ) then
    raise exception 'Compartir viaje está deshabilitado';
  end if;

  select t.status
    into v_status
  from public.trips t
  where t.id = p_trip_id
    and t.passenger_id = v_uid
    and t.channel = v_channel;

  if not found then
    raise exception 'Viaje no encontrado o no autorizado';
  end if;

  if v_status not in (
    'driver_assigned',
    'driver_arriving',
    'driver_waiting',
    'in_progress',
    'emergency'
  ) then
    raise exception 'El viaje ya no está activo';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.trip_share_links (
    trip_id,
    passenger_id,
    channel,
    token_hash,
    expires_at
  )
  values (
    p_trip_id,
    v_uid,
    v_channel,
    v_hash,
    v_expires_at
  );

  return jsonb_build_object(
    'token', v_token,
    'expires_at', v_expires_at
  );
end;
$$;

create or replace function public.get_shared_trip(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_row record;
  v_is_active boolean;
begin
  if p_token is null or p_token !~ '^[0-9a-fA-F]{64}$' then
    return jsonb_build_object(
      'ok', false,
      'active', false,
      'reason', 'invalid'
    );
  end if;

  v_hash := encode(
    extensions.digest(lower(p_token), 'sha256'),
    'hex'
  );

  select
    l.expires_at,
    t.status,
    r.pickup_address,
    r.pickup_latitude,
    r.pickup_longitude,
    r.destination_address,
    r.destination_latitude,
    r.destination_longitude,
    coalesce(nullif(trim(du.full_name), ''), 'Conductor Express') as driver_name,
    dp.latitude as driver_latitude,
    dp.longitude as driver_longitude,
    dp.location_updated_at,
    dv.brand as vehicle_brand,
    dv.model as vehicle_model,
    dv.color as vehicle_color,
    dv.plate as vehicle_plate
  into v_row
  from public.trip_share_links l
  join public.trips t on t.id = l.trip_id
  join public.ride_requests r on r.id = t.ride_request_id
  join public.driver_profiles dp on dp.id = t.driver_id
  join public.users du on du.id = t.driver_id
  left join lateral (
    select
      v.brand,
      v.model,
      v.color,
      v.plate
    from public.driver_vehicles v
    where v.driver_id = t.driver_id
      and v.is_active = true
    order by v.updated_at desc, v.created_at desc
    limit 1
  ) dv on true
  where l.token_hash = v_hash
    and l.revoked_at is null
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'active', false,
      'reason', 'invalid'
    );
  end if;

  if v_row.expires_at <= now() then
    return jsonb_build_object(
      'ok', true,
      'active', false,
      'reason', 'expired'
    );
  end if;

  v_is_active := v_row.status in (
    'driver_assigned',
    'driver_arriving',
    'driver_waiting',
    'in_progress',
    'emergency'
  );

  if not v_is_active then
    return jsonb_build_object(
      'ok', true,
      'active', false,
      'reason', 'ended',
      'status', v_row.status
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'active', true,
    'status', v_row.status,
    'driver_name', v_row.driver_name,
    'vehicle', jsonb_strip_nulls(
      jsonb_build_object(
        'brand', v_row.vehicle_brand,
        'model', v_row.vehicle_model,
        'color', v_row.vehicle_color,
        'plate', v_row.vehicle_plate
      )
    ),
    'driver_location', jsonb_strip_nulls(
      jsonb_build_object(
        'latitude', v_row.driver_latitude,
        'longitude', v_row.driver_longitude,
        'updated_at', v_row.location_updated_at
      )
    ),
    'pickup', jsonb_strip_nulls(
      jsonb_build_object(
        'address', v_row.pickup_address,
        'latitude', v_row.pickup_latitude,
        'longitude', v_row.pickup_longitude
      )
    ),
    'destination', jsonb_strip_nulls(
      jsonb_build_object(
        'address', v_row.destination_address,
        'latitude', v_row.destination_latitude,
        'longitude', v_row.destination_longitude
      )
    )
  );
end;
$$;

revoke execute on function public.create_trip_share_link(uuid, text)
  from public, anon;
grant execute on function public.create_trip_share_link(uuid, text)
  to authenticated, service_role;

revoke execute on function public.get_shared_trip(text)
  from public;
grant execute on function public.get_shared_trip(text)
  to anon, authenticated, service_role;
