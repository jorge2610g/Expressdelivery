-- Impide que un pasajero registre pagos directamente desde la API.
-- Antes, la regla payments_insert_payer permitía insertar cualquier monto
-- para un viaje propio, y el disparador de billetera liquidaba ese monto.
-- Los cobros reales se crean dentro de funciones del servidor que se ejecutan
-- con permisos propios (advance_trip, advance_delivery), que no dependen de esta regla.
drop policy if exists payments_insert_payer on public.payment_transactions;
