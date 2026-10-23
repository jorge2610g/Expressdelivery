# Deudas por ajustes administrativos — 2026-10-23

## Comportamiento

- Adminexpress crea una deuda pendiente solo por la porción de un descuento que deja la billetera bajo cero. Si el ajuste consume saldo existente y no crea sobregiro, no genera deuda.
- La deuda administrativa es distinta de las comisiones del conductor y de las deudas por cancelación. Conserva el motivo de ajuste original.
- El pasajero con deuda no puede solicitar Taxi; sus solicitudes de Envíos se conservan. Conductores con deuda no pueden conectarse, enviar ofertas, recibir asignaciones ni aceptar Taxi, Envíos o Delivery. Un conductor sin servicio activo se desconecta cuando se registra la deuda; un trabajo que ya estaba activo puede finalizar.
- Un abono verificado en billetera o un crédito administrativo reduce la deuda pendiente FIFO. La cuenta queda habilitada cuando ya no tiene deuda administrativa abierta.
- La billetera expone monto y motivo. Preview solo ofrece simulación para cuentas QA; nunca se crea un cobro real.

## Migraciones coordinadas

1. `20261023192317_admin_adjustment_wallet_debt.sql` (Adminexpress): tabla privada, creación de deuda desde el RPC de ajuste, crédito/liquidación administrativa y lectura/listado con alcance por zona, rol, entorno y moneda.
2. `20261023192321_enforce_admin_adjustment_debt.sql` (Expressdelivery): guardas server-side de pasajero/conductor, desconexión segura, lectura propia y conciliación de recargas verificadas.

Aplicar ambas migraciones en ese orden antes de desplegar la UI del panel y cliente. No modificar migraciones históricas ni probar con cuentas/dinero reales.
Los saldos negativos antiguos no se convierten automáticamente en deuda porque pueden corresponder a comisiones; se deben revisar en la auditoría antes de clasificarlos.

## Seguridad

- La tabla de deudas no concede acceso directo a `anon` o `authenticated`; las lecturas y mutaciones usan RPCs.
- Los RPCs administrativos validan rol/módulo `payments`, entorno ligado a identidad, zona efectiva e idempotencia.
- Los pagos externos se finalizan únicamente con la verificación server-side existente y con rol `service_role`.
- Las reglas de cancelación quedan intactas y siguen consultando su tabla original.
