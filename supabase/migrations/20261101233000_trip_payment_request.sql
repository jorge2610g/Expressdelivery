-- Botón "Cobrar" del conductor.
-- Registra el momento en que el conductor pide el cobro en un viaje en curso.
-- Ese momento hace visible el QR de pago del conductor al pasajero.
-- No cambia montos, tarifas, estados de viaje, cobros ni billetera.
-- Requiere 20261101232624_driver_payment_qr.sql (payment_qr_path y bucket), ya aplicada.

alter table public.trips
  add column if not exists payment_requested_at timestamptz;

-- El conductor del viaje lo llama mientras el viaje está en curso.
create or replace function public.request_trip_payment(p_trip_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_at timestamptz;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión no válida.';
  end if;

  update public.trips t
     set payment_requested_at = coalesce(t.payment_requested_at, now())
   where t.id = p_trip_id
     and t.driver_id = v_uid
     and t.status = 'in_progress'
     and t.channel = coalesce((
       select b.environment
       from public.account_runtime_bindings b
       where b.user_id = v_uid
     ), 'production')
  returning t.payment_requested_at into v_at;

  if v_at is null then
    raise exception 'El viaje no está en curso.';
  end if;

  return v_at;
end;
$$;

revoke all on function public.request_trip_payment(uuid) from public;
grant execute on function public.request_trip_payment(uuid) to authenticated;

-- El pasajero puede leer el QR en dos momentos: cuando el conductor pidió el
-- cobro (en curso) o cuando el viaje está completado con cobro pendiente.
create or replace function public.passenger_can_view_payment_qr(p_path text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select auth.uid() is not null
    and public.is_account_active()
    and p_path is not null
    and exists (
      select 1
      from public.driver_profiles dp
      join public.trips t on t.driver_id = dp.id
      where dp.payment_qr_path = p_path
        and dp.id::text = split_part(p_path, '/', 1)
        and t.passenger_id = auth.uid()
        and (
          (t.status = 'in_progress' and t.payment_requested_at is not null)
          or (t.status = 'completed' and t.payment_status = 'pending')
        )
        and t.channel = coalesce((
          select b.environment
          from public.account_runtime_bindings b
          where b.user_id = auth.uid()
        ), 'production')
    );
$$;

create or replace function public.passenger_trip_driver_payment_qr(p_trip_id uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select dp.payment_qr_path
  from public.trips t
  join public.driver_profiles dp on dp.id = t.driver_id
  where t.id = p_trip_id
    and t.passenger_id = auth.uid()
    and (
      (t.status = 'in_progress' and t.payment_requested_at is not null)
      or (t.status = 'completed' and t.payment_status = 'pending')
    )
    and dp.payment_qr_path is not null
    and public.passenger_can_view_payment_qr(dp.payment_qr_path)
  limit 1;
$$;
