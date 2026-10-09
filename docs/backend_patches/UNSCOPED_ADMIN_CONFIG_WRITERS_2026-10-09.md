# Riesgo P0 — funciones administrativas que aún escriben configuración real

Auditoría **de solo lectura** a Supabase principal `zgpijrznvaskgcmauwxx` el
9 de octubre de 2026. Ningún SQL de esta auditoría modificó datos.

## Hallazgo probado

La UI Admin Preview utiliza el mismo proyecto Supabase que Producción,
y las cuentas pueden tener permisos administrativos en ambos canales.
Una verificación de acceso a `admin` **no distingue el canal de origen**.

La inspección de `pg_proc` (definición, firma, `SECURITY DEFINER` y
`has_function_privilege`) confirmó que las siguientes RPC
**se pueden invocar con la credencial authenticated** (además de requerir
las comprobaciones administrativas que existen dentro del cuerpo).
Sus firmas NO contienen un parámetro `p_channel`:

| RPC | Recurso de Producción en riesgo de modificación |
| --- | --- |
| `admin_upsert_zone_v3` | zonas/radio y sus metadatos |
| `admin_upsert_zone_polygon` | polígonos geográficos |
| `admin_upsert_fare_rule` | tarifas |
| `admin_upsert_country_coverage_v2` | países, moneda y habilitación |
| `admin_update_zone_landing` | configuración de página y módulos por zona |
| `admin_upsert_driver_document_requirement` | requisitos de documentos |
| `admin_delete_driver_document_requirement` | requisitos de documentos |
| `admin_upsert_zone_payment_method` | métodos de pago de zonas |
| `admin_delete_zone_payment_method` | métodos de pago de zonas |
| `admin_set_zone_payment_provider` | proveedor de pago por zona |

También aparecen definiciones heredadas sin canal:
`admin_upsert_zone` (dos firmas), `admin_upsert_zone_v2` y
`admin_upsert_country_coverage`. Se deben analizar usos antes de
retirarlas o bloquearlas. Algunas llamadas pueden originarse desde
Producción instalada previamente: **no revocar EXECUTE a ciegas**.

Separadamente, `admin_zone_coverage_save` SÍ recibe `p_channel`;
originalmente aceptaba `preview` y luego escribía zonas reales.
**Esta ruta concreta ya fue corregida** con el fail-closed de la
migración Prod `20261009222741`. El resto de funciones listadas aquí
**siguen pendientes**, por lo que no existe aislamiento completo.

## Por qué NO basta cambiar el panel

Las correcciones ya desplegadas desde Adminexpress PR #51 dirigen los
formularios Preview a `admin_environment_config` (shadow), y el panel
bloquea módulos de pagos/publicación que no son seguros para Preview.
Esto mitiga errores desde **esa interfaz**, pero una llamada antigua,
otra pantalla o un cliente directamente conectado puede invocar RPC
sin canal. La autenticación de administrador NO prueba que la solicitud
provenga de Producción.

No afirmar aislamiento backend total ni dar por liberada la publicación
hasta tener separación de permisos aplicada en servidor y probada.
Si una cuenta puede operar en ambos entornos dentro del mismo backend,
`p_channel` recibido desde cliente no constituye prueba segura del origen.

## Fase actual y siguientes protecciones

1. Guard de `admin_zone_coverage_save`: **APLICADO** en QA físico y
   Producción, con respaldo y comprobación de paridad funcional de
   Producción. Registro versionado en el PR #145. No ejecutar de nuevo.
2. **No revocar** directamente las firmas RPC de Producción: pueden
   estar siendo usadas por clientes instalados; inspeccionar
   dependencias de SQL/Edge y llamadas del Admin y Android actuales.
3. Planificar una frontera de autorización **del servidor**, con
   identidad QA sin permisos a escrituras de Producción o infraestructura
   QA física alineada en esquema. Con `super_admin` de doble acceso
   y RPC legacy sin canal todavía no hay garantía fuerte.
4. Ensayar denegaciones y accesos permitidos con usuarios y zonas
   sintéticos en QA, y certificar regresiones para clientes anteriores.
5. Actualizar Producción por pasos, con rollback listo, monitoreo,
   validación de metadatos reales y ventanas de rollback.

## Pruebas automáticas disponibles

`.github/workflows/validate-preview-backend-zone-guard.yml` y
`supabase/migrations/20261009222741_admin_zone_coverage_preview_fail_closed_20261009.sql`
validan que la única diferencia en el cuerpo SQL del RPC guardado
es la denegación temprana de Preview. Las pruebas autenticadas en el
proyecto QA aprobaron denegación Preview y rechazo de Producción a
cuenta QA-only. La simulación de una sesión de administrador contra
Producción fue bloqueada por controles de la herramienta, por lo que
**NO está certificada como prueba ejecutada**.

**La revisión de código y el test QA no prueban el aislamiento de
las RPC heredadas sin canal.**
