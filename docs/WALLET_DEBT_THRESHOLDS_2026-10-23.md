# Umbrales de deuda de billetera — 2026-10-23

## Regla de producto

Admin configura un tope en moneda local para pasajeros y otro para conductores, por zona y contexto de cuenta. El backend bloquea únicamente cuando `deuda pendiente del rol en esa zona > tope`. Por ejemplo, con 10 BOB, 9 BOB y 10 BOB permiten continuar; 10,01 BOB bloquea. El valor 0 (también el predeterminado sin registro) conserva el comportamiento anterior: cualquier deuda positiva bloquea.

Se agregan deuda de ajustes administrativos y deuda de cancelación impaga. No se suma el saldo de comisiones. El rol se evalúa según la acción: pasajero al solicitar Taxi; conductor al conectarse, ofertar/aceptar Taxi, Envíos o Delivery. La restricción de pasajero no cambia el flujo de Envíos.

## Seguridad y cambios

- Configuración almacenada en `zone_wallet_debt_limits`, llave `(channel, zone_id)`. RLS habilitado y acceso directo revocado; lectura/escritura mediante RPCs administrativas que toman entorno de la cuenta, exigen `payments` para operadores y aplican `admin_effective_zone_id`.
- Auditoría de cambios en `zone_wallet_debt_limit_audit` con actor, zona, canal, moneda y valores antes/después.
- Reducción del tope de conductor desconecta inmediatamente solo a conductores libres que excedan el nuevo valor; viajes y entregas activos terminan normalmente.
- Mensajes de la app dirigen a Pagos y billetera, sin códigos SQL ni proveedor de pago.

## Migraciones

Aplicar en este orden en la base compartida:

1. `20261023221937_wallet_debt_threshold_settings` — tabla, RPCs y auditoría del panel.
2. `20261023221938_enforce_wallet_debt_thresholds` — agrega el cálculo y reemplaza los guards del servidor.

No reejecutar ni modificar migraciones históricas. Con la configuración ausente, el tope se interpreta como cero, por lo que el despliegue no relaja bloqueos existentes.

## QA y publicación

Pruebas de contrato: `test/wallet_debt_threshold_contract_test.dart`, `test/cancellation_debt_messages_test.dart` y `test/admin_adjustment_debt_contract_test.dart`. Admin: `test/admin_wallet_debt_limits_test.dart` y `test/admin_zonal_debt_management_test.dart`.

Para QA, usar una cuenta aislada y topes de Preview; verificar cada rol con deuda menor, igual y mayor al límite. No generar deudas ni pagos reales. La distribución móvil debe ser únicamente la candidata oficial `com.express.usuario1`; no reutilizar un versionCode ya usado y no promover a Producción sin aprobación separada.
