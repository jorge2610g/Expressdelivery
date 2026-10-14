# Guard P0 de zonas en el backend — desplegado y verificado parcialmente

**Fecha:** 2026-10-09  
**Proyecto principal:** `zgpijrznvaskgcmauwxx`  
**QA físico:** `xbphilqezmwfjfpdbwad`  
**Migración principal:** `20261009222741_admin_zone_coverage_preview_fail_closed_20261009.sql`

## ¿Qué se implementó?

La RPC `public.admin_zone_coverage_save(p_channel,...)` aceptaba
`p_channel='preview'` y luego actualizaba `service_zones` y
`service_zone_polygons` reales. Se insertó un guard después del
chequeo administrativo y **antes** de cualquier modificación:

```sql
if p_channel='preview' then
  raise exception 'Esta cobertura es exclusiva de QA: utiliza la configuración aislada de Preview';
end if;
```

La firma RPC, permisos existentes, tratamiento `production`,
validación radio/polígono y resto del cuerpo NO se alteraron.

## Evidencia de pruebas

1. Recuperamos la definición real original de `pg_proc` mediante
   `pg_get_functiondef` y preservamos un rollback exacto en
   `docs/backend_patches/rollback_admin_zone_coverage_save_before_preview_guard_20261009.sql`.
2. Comprobamos equivalencia normalizada exacta del cuerpo SQL antes
   y después, al eliminar únicamente el guard propuesto (2872
   caracteres normalizados en ambos cuerpos). Ninguna otra
   instrucción de Producción cambió.
3. Se aplicó la función en el proyecto físico QA, bajo la migración
   `qa_coverage_rpc_preview_fail_closed_20261009`, y se verificó con
   transacción revertida y rol admin QA autenticado:
   - `preview` fue rechazado con el mensaje QA esperado;
   - `production` fue rechazado por permisos del admin QA-only;
   - ambos casos se realizaron sin modificar zonas reales.
4. Se aplicó la misma función en el proyecto principal usando la
   migración registrada `20261009222741`.
5. Consultas a `pg_proc` confirmaron en Producción la firma idéntica,
   `SECURITY DEFINER`, permiso EXECUTE autenticado intacto, y
   guard `preview` ubicado antes de la primera escritura.
6. Los hashes MD5 del JSON ordenado y los conteos completos de SIETE
   tablas operativas antes/después fueron idénticos:
   `app_settings`, `driver_document_requirements`, `fare_rules`,
   `service_countries`, `service_zone_polygons`, `service_zones`
   y `zone_payment_methods`.
7. Se intentó una prueba con contexto administrativo simulado contra
   Producción; la herramienta de seguridad bloqueó esa operación,
   por lo que **NO** hay prueba de rol producción ejecutada.
   No se debe registrar como aprobada.

## Riesgo aún abierto

**Este cambio NO certifica que Preview y Producción estén aislados de
forma completa.** Todavía hay RPC privilegiadas sin parámetro de
entorno (`admin_upsert_zone_v3`,
`admin_upsert_zone_polygon`, `admin_upsert_fare_rule`,
`admin_upsert_country_coverage_v2`, funciones de pagos y otras).
La cuenta super_admin principal tiene acceso autorizado a ambos
canales, lo que impide conocer el origen UI exclusivamente desde
`is_admin()`. Una RPC sin canal sigue expuesta a una llamada
administrativa manual o versión cliente anterior.

Mantener abierto issue #141 y propuesta #144; **no revocar permisos
masivamente** ni modificar usuarios activos sin auditoría de clientes.
La solución de frontera requiere credenciales con permiso exclusivo
por entorno o infraestructura física QA completa y compatible;
en el proyecto físico QA faltaban una tabla y seis RPC frente a
Producción. El viejo Preview Admin publicado sigue dirigiendo sus
configuraciones editables al almacenamiento shadow.

## Rollback

El archivo SQL de rollback preserva literalmente la función anterior.
Restaurarla reabre la vulnerabilidad, por lo que **solo** se justifica
ante una interrupción real de Producción y con aprobación explícita.
No restaurar bases completas ni borrar filas como reversión de este
cambio. No se generó APK, AAB ni publicación Android.

## Siguiente prueba antes del uso general

Realizar con cuentas de test y navegador una edición inocua de radio
o polígono en el **panel QA shadow**, verificar que se conserva allí y
que los conteos/hashes de zonas reales permanecen sin cambios.
Después repetir pruebas de precios, KYC manual y recorrido completo
de viaje en Preview con usuarios/conductores sintéticos. Falta
certificar funciones legacy y autorización de backend antes de
activar operaciones que impliquen fondos o viajes reales.
