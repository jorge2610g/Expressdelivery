-- QR de pago del conductor ("Mi QR de pago").
-- Alcance: referencia del archivo en driver_profiles, bucket privado y accesos.
-- No cambia montos, tarifas, estados de viaje, cobros ni triggers de billetera.

alter table public.driver_profiles
  add column if not exists payment_qr_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'driver-payment-qr',
  'driver-payment-qr',
  false,
  5242880,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
  set public = false,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

-- El conductor solo escribe y lee dentro de su propia carpeta <uid>/...
drop policy if exists driver_payment_qr_insert_self on storage.objects;
create policy driver_payment_qr_insert_self on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'driver-payment-qr'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists driver_payment_qr_read_self on storage.objects;
create policy driver_payment_qr_read_self on storage.objects
  for select to authenticated
  using (
    bucket_id = 'driver-payment-qr'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists driver_payment_qr_delete_self on storage.objects;
create policy driver_payment_qr_delete_self on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'driver-payment-qr'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

-- Pasajero: puede leer el archivo solo si es el QR vigente del conductor de un
-- viaje propio, que ya está completado y con el cobro pendiente, en el mismo
-- entorno (Preview o Producción) de su cuenta.
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
        and t.status = 'completed'
        and t.payment_status = 'pending'
        and t.channel = coalesce((
          select b.environment
          from public.account_runtime_bindings b
          where b.user_id = auth.uid()
        ), 'production')
    );
$$;

drop policy if exists driver_payment_qr_read_passenger_cobro on storage.objects;
create policy driver_payment_qr_read_passenger_cobro on storage.objects
  for select to authenticated
  using (
    bucket_id = 'driver-payment-qr'
    and public.passenger_can_view_payment_qr(name)
  );

-- Devuelve la ruta del QR del conductor de un viaje propio solo en el paso de
-- cobro. Si no cumple, devuelve null y la pantalla del pasajero no cambia.
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
    and t.status = 'completed'
    and t.payment_status = 'pending'
    and dp.payment_qr_path is not null
    and public.passenger_can_view_payment_qr(dp.payment_qr_path)
  limit 1;
$$;

revoke all on function public.passenger_trip_driver_payment_qr(uuid) from public;
grant execute on function public.passenger_trip_driver_payment_qr(uuid) to authenticated;

-- El conductor registra o quita la referencia de su QR. Solo acepta rutas
-- dentro de su carpeta que existan en el bucket privado.
create or replace function public.set_my_payment_qr_path(p_path text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión no válida.';
  end if;

  if p_path is not null then
    if split_part(p_path, '/', 1) <> v_uid::text
       or p_path !~ '^[0-9a-f-]{36}/qr/[0-9]+\.(png|jpe?g|webp)$' then
      raise exception 'Ruta de QR no válida.';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'driver-payment-qr' and o.name = p_path
    ) then
      raise exception 'El archivo del QR no existe.';
    end if;
  end if;

  update public.driver_profiles
     set payment_qr_path = p_path
   where id = v_uid;

  if not found then
    raise exception 'Perfil de conductor no encontrado.';
  end if;

  return p_path;
end;
$$;

revoke all on function public.set_my_payment_qr_path(text) from public;
grant execute on function public.set_my_payment_qr_path(text) to authenticated;
