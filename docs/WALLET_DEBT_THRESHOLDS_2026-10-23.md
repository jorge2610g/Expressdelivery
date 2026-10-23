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

## Estado real de implementación y publicación — 2026-10-23

### Código y configuración

- La lógica del tope está en `main` desde el commit `7b0feca91c91d8c2400057aaead5c7c73b4558fc` (`feat: enforce zonal wallet debt thresholds`, PR #288).
- El Android oficial declara ahora `1.6.3+146`. El cambio mínimo de versión se integró mediante PR #289, commit `2d578c42df44640c2d3388d472bc7de0b55b81e7`.
- El panel oficial administra dos límites separados (pasajero/conductor) por zona en Producción; el usuario decide los importes. No se configuró un monto por cuenta de Codex.
- La migración de configuración y la migración de enforcement constan aplicadas en el proyecto Supabase de Producción `zgpijrznvaskgcmauwxx`. No volver a aplicarlas.
- La web Admin y la web oficial de Express fueron desplegadas previamente. La siguiente candidata es únicamente Android; no existe una publicación de esta build a Producción.

### Contador de Play y fallos de preparación

- Google Play informó que `versionCode 145` ya estaba usado; la build no se compiló en ese intento. El AAB anterior de build 145 corresponde al SHA `2c8f57d2d01574714b24afd68614dd8453d2a1eb` y su workflow confirmó carga exitosa en la pista Internal, sin cambios en Producción.
- El gate interno aún registra build de Producción 141 y próximo 145. Para no reutilizar un código ya usado, se avanzó solo `next_production_build_number` a 146; `production_store_build_number` se dejó en 141. Esto conserva el baseline declarado para Producción y reserva el siguiente código libre observado en Play.
- El primer candidato 145 (ID `146b84df-de3f-4d05-8f77-dd95a1d337e9`, run `40035544713`) fue detenido por el preflight de Play.
- El primer candidato 146 (ID `0e25cc04-5297-464a-af6d-0cef201453dc`, run `40035845636`) fue detenido porque el código fuente aún decía `+145`.
- El siguiente intento desde una rama de trabajo (run `40035929486`) fue rechazado por el control OIDC, que solo autoriza el actor/rama/workflow configurado para `main`; no produjo artefactos ni publicación.

### Candidata oficial actualmente en curso

- Candidata en cola: `924d2773-ff8d-4292-9a7d-d583df5a0574`, versión `1.6.3+146`.
- Fuente que debe tomar el workflow: `main`, posterior a PR #289; paquete `com.express.usuario1` y firma oficial existente.
- Workflow iniciado: `40036108664` — [ver ejecución](https://github.com/jorge2610g/Expressdelivery/actions/runs/40036108664).
- Se registró expresamente `QA PENDIENTE - PRUEBA MANUAL EN INTERNAL`: Codex no realizará pruebas en emuladores. La prueba funcional queda para el propietario tras instalar desde Pruebas internas.
- Autorización entregada: `AUTORIZO APK+AAB PRUEBAS INTERNAS`. El destino permitido es Google Play Internal; no promover a Producción.
- **Al actualizar este documento, el workflow está compilando; la carga del AAB todavía no está confirmada.** Marcarlo listo solo después de que la ejecución termine y la fila `build_jobs` quede `ready` con los artefactos y hashes.

### Continuación para otra IA

1. Consultar `gh run view 40036108664 --repo jorge2610g/Expressdelivery` y `gh run watch` hasta que termine.
2. Si falla, inspeccionar `gh run view 40036108664 --repo jorge2610g/Expressdelivery --log-failed`; no afirmar que se subió.
3. Si termina en éxito, verificar en Producción Supabase que la candidata `924d2773-ff8d-4292-9a7d-d583df5a0574` quede `ready`, `build_number=146`, con APK/AAB, SHA-256, firma `production` y URL del run.
4. Confirmar en el log del job que Play aceptó `com.express.usuario1`, build 146, track `internal`, y que indica “sin cambios en Producción”. Entregar al propietario la URL de instalación del APK o la ficha/lista de Internal.
5. Dejar QA manual pendiente. No certificar, aprobar, promover ni publicar a Producción hasta recibir la verificación explícita del propietario.
6. El monto del tope debe configurarlo el administrador por zona para pasajero y conductor. No inferir ni asignar 10 Bs por el ejemplo conversacional.
