# Pruebas locales de aceptación de taxi (PostgreSQL 15 aislado)

Estado: **validado solo en PostgreSQL local**. No validado en Supabase ni en producción.

## Entorno
- Contenedor Docker `express-qa-pg15`, imagen `postgres:15`, enlazado a `127.0.0.1:54399`. Datos sintéticos. Sin conexión a servicios externos.
- Contraseña generada localmente; no se guarda en el repositorio. El script usa `docker exec` (acceso local del contenedor).

## Reproducción
1. `docker run -d --name express-qa-pg15 -e POSTGRES_PASSWORD=<local> -e POSTGRES_DB=express_qa -p 127.0.0.1:54399:5432 postgres:15`
2. `bash docs/pending_migrations/local_qa/run_local_qa.sh qa_baseline baseline` (función del repositorio).
3. `bash docs/pending_migrations/local_qa/run_local_qa.sh qa_patched patched` (con la migración de `docs/pending_migrations/20261016_select_ride_offer_expiry_guard.sql`).

## Contenido
- `schema_stub.sql`: tablas mínimas con las columnas y tipos de producción (metadatos, sin filas), `auth.uid()` replicado.
- `functions_from_repo_latest.sql`: funciones copiadas de las **últimas** migraciones que las definen: `same_operational_scope` (035), `normalize_runtime_channel` / `is_active_audit_user` / `sync_trip_runtime_channel` (089, con `alter` y permisos de 090), `guard_request_runtime_channel` (091), `select_ride_offer` (034) y `select_ride_offer_v2` (089).
- `triggers_from_repo_baseline.sql`: los dos triggers de canal de 089.
- `test_helper.sql`, `seed_base.sql`: envoltorio de prueba y datos sintéticos (un pasajero y dos conductores de auditoría ficticios).
- `results_*.txt`: salidas de las ejecuciones.

## Resultados
| Escenario | Función del repositorio | Con `0eb7cb5` |
|---|---|---|
| Oferta vigente | aceptada | aceptada |
| Oferta vencida | rechazada | rechazada |
| `expires_at` nulo | **aceptada (defecto)** | **rechazada** |
| Segunda aceptación | rechazada | rechazada |
| Conductor intenta asignarse | rechazado | rechazado |
| Control: pasajero tras rechazo | aceptada | aceptada |
| Bloqueo `FOR UPDATE` (dos transacciones) | A asigna; B espera y es rechazada | igual |
| Carrera (30 / 50 / 50 repeticiones) | 30/30 un solo ganador, 0 inconsistencias | 30/30, 50/50, 50/50 |

Notas: en la versión del repositorio la prueba de `expires_at` nulo es un FAIL (defecto confirmado). La corrección lo resuelve.

## Diferencias con Supabase (no validado)
- **RLS:** no aplicado. Las funciones `security definer` no dependen de RLS, pero el acceso directo a las tablas sí.
- **Triggers excluidos, con motivo:**
  - Notificaciones y push (`trg_dispatch_push_notification`, `trg_notify_ride_offer`, `trg_notify_available_ride`, `trg_log_*`): podrían enviar FCM o escribir eventos. Excluidos para no tocar push.
  - `trg_driver_offer_deadline` y `trg_enforce_driver_offer_minimum_lifetime`: **pueden modificar `expires_at` en producción.** No replicados. Riesgo principal: hay que verificarlo en una rama de Supabase antes de desplegar.
  - Guardas de suscripción, KYC, cobertura, pagos y redondeo de tarifas: no intervienen en la aceptación.
  - `trg_guard_driver_offer_runtime_channel`: no replicado.
- **Autenticación:** `auth.uid()` lee `request.jwt.claim.sub` como Supabase. No hay GoTrue ni JWT real.
- **Extensiones:** ninguna. `gen_random_uuid()` es nativo en PostgreSQL 15. Supabase podría usar otra versión; no verificada.
- **Restricciones:** sin claves foráneas adicionales, `check`, índices ni enums de producción.
- **Aislamiento:** PostgreSQL usa `READ COMMITTED` por defecto, igual que el uso habitual de Supabase. La concurrencia se comprobó con transacciones independientes, no a través de PostgREST ni del pool de conexiones.

## No validado
- Comportamiento real de los triggers de vencimiento de producción (ver arriba).
- Concurrencia a través de la API de Supabase.
- Cualquier efecto sobre Taxi o Envíos en producción.
