> **ACTUALIZACIÓN 2026-10-09 — APLICADO Y VERIFICADO EN PRODUCCIÓN.**
> La propuesta de este documento fue aplicada después del despliegue exclusivo
> de Adminexpress Preview (PR #53) y de la prueba del guard en QA físico.
> Migración registrada: `20261009232017_admin_distance_fare_steps_preview_fail_closed_20261009`.
> `pg_proc` confirma que `p_channel='preview'` se rechaza ANTES del
> DELETE/INSERT; permisos `authenticated` y bloqueo de `anon`, firma
> y código de Producción permanecen como estaban.
> Fingerprints y conteos antes/después **idénticos**:
> `zone_distance_fare_steps` 0 filas,
> `fare_rules` 3, `service_zones` 2,
> `zone_service_catalog` 10.
> El sitio web raíz de Producción no se compiló ni modificó con la
> actualización de Preview. **No certifica** RPC sin canal ni
> caminos heredados con default `production`.
>
> La sección a continuación conserva el procedimiento de propuesta original
> como trazabilidad histórica de la evaluación.

---

# P0 adicional: tarifas por distancia de Preview podían alterar las reglas reales

**Descubierto el 9 de octubre de 2026**, durante la auditoría de funciones
administrativas con parámetros `p_channel`.

## Hallazgo demostrado

El editor de Adminexpress `lib/admin_distance_fares.dart` llamaba
`admin_distance_fare_steps_replace(p_channel=widget.channel,...)` desde
ambas páginas. La RPC original de Producción autorizaba `preview` y
después ejecutaba `DELETE` y `INSERT` sobre la tabla real
`public.zone_distance_fare_steps`. **No existía sombra QA para esos
escalones en el editor**. Las tarifas pudieron verse afectadas si un
administrador probaba la modificación desde Preview.

## Tratamiento en dos capas

1. **Frontend:** Adminexpress PR #53 reemplaza lectura/escritura Preview
   por `AdminEnvironmentStore.previewGet/previewUpsert` sobre el módulo
   `zone_distance_fare_steps`, clave determinística
   `zone_id::service_key`, y mantiene **sin cambios** las llamadas
   reales desde Producción.
2. **Backend:** esta rama propone agregar una única sentencia de
   rechazo `if p_channel='preview' then raise exception ...;`
   después de la autorización y antes de la primera escritura. No
   modifica SQL original restante, defaults ni rutas de Producción.
3. **Previo a deploy:** conservar snapshot de rollback exacto,
   `docs/backend_patches/rollback_admin_distance_fare_steps_replace_pre_guard_20261009.sql`.
   El rollback reabre el problema; no ejecutar preventivamente.
4. **Pruebas QA físico:** el SQL candidato se aplicó al proyecto físico
   `xbphilqezmwfjfpdbwad` con
   `qa_distance_fare_steps_preview_fail_closed_20261009`. Test en
   transacción revertida usando rol `authenticated` y superadmin
   `allow_preview=true`, `allow_production=false`: Preview denegado
   con mensaje QA esperado; la llamada Production denegada por
   `admin_environment_allowed`. **QA físico aún no tiene la tabla
   real de escalones**, por lo que no se ejecutaron ni se certificaron
   escrituras Production de esa función allí.
5. **Static CI:** `.github/workflows/verify-preview-distance-fare-guard.yml`
   verifica que únicamente se agrega el rechazo y que ocurre antes de
   `DELETE/INSERT`.

## Dependencias y precauciones

- `admin_distance_fare_steps_replace(..., p_channel text DEFAULT
  'production')` tiene un valor por defecto en SQL. La función de
  guardia solo protege clientes que envían explícitamente `preview`.
  Las llamadas que omiten canal continúan haciendo lo mismo que antes.
  **Cambiar ese default sin auditar clientes instalados podría
  interrumpir Producción.**
- `admin_distance_fare_steps_get` todavía puede leer tarifas reales
  desde una solicitud `preview`; el nuevo editor Preview **ya no
  llama** esa RPC. Debe evaluarse una denegación de lectura del servidor
  después de auditar dependencias históricas.
- Todas las funciones legacy sin canal siguen pendientes en el issue
  de seguridad Expressdelivery #141.
- La sombra `admin_environment_config` es una configuración de
  laboratorio, **no** participa automáticamente del cálculo real de
  precios del cliente. No declarar prueba integral de cotización
  válida usando solo esa pantalla.
- No se ha publicado APK, AAB ni tarifas nuevas en Producción por
  las pruebas QA físicas.

## Validación posterior al despliegue

Si se aplica el guard al backend principal, comparar por lecturas
`SELECT` conteos y fingerprints de `zone_distance_fare_steps`,
`fare_rules`, `service_zones` y `zone_service_catalog` antes/después.
Verificar por `pg_proc` firma, privileges, ubicación del guard y
preservación semántica del cuerpo. Nunca usar datos ni pagos reales
como prueba. No certificar aislamiento backend hasta abordar las
otras RPC sin canal y la identidad dual de administrador.
