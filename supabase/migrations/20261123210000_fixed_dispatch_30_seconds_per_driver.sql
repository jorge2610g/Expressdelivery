-- Precio fijo uno a uno: cada conductor tiene 30 segundos para aceptar (antes 15).
update public.app_settings set fixed_dispatch_seconds = 30 where id = true;
