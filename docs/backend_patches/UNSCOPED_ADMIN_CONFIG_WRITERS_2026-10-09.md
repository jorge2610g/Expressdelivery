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

Separadamente, `admin_zone_coverage_save` SÍ recibe `p_channel`
pero su definición actual admite `preview` y luego llama a
`admin_upsert_zone_v3` sobre zonas reales: es el guard P0 del PR #144.

## Por qué NO basta cambiar el panel

Las correcciones en la rama de Adminexpress PR #51 dirigen los
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

## Secuencia segura recomendada

1. Mantener actuales PR #51, #142 y #144 como borradores. No desplegar
   migraciones ni fusionar editores todavía.
2. Identificar *todas* las llamadas reales a estas RPC desde versiones
   actuales **y versiones Android instaladas**, más triggers,
   dependencias SQL y edge functions.
3. Elegir frontera verificable: privilegios administradores QA sin acceso
   de Producción a funciones legacy, **o** proyecto físico Preview con
   los esquemas y pruebas necesarios. Verificar que ninguna identidad
   QA tenga autorización para escribir zona/tarifa real.
4. Construir nuevas RPC canalizadas y/o guards por **rol/autorización
   del lado del servidor**; no depender del valor de canal enviado
   libremente por el cliente.
5. Ensayar en base física QA con usuarios y zonas sintéticos, validar
   autorización denegada/permitida, tarifas, viajes, cobertura
   radio/polígono, pago, tiempo real, y comportamiento de Android viejo.
6. Documentar backup y revertir nueva función/GRANT ante regresiones,
   con métricas y control de despliegue; recién entonces migrar a
   Producción en ventana controlada.

## Pruebas automáticas disponibles

`.github/scripts/check_preview_zone_sql_guard.py` compara exactamente
la definición original de la función geográfica con la propuesta:
después de remover el único bloque fail-closed QA, ambos cuerpos SQL
son idénticos. También valida que el guard se ejecuta antes de escribir
datos reales y que el SQL termina con `end $$;`.

**Esta es una revisión estática; no ejecuta SQL ni sustituye
tests integrados en Supabase.** El resto de RPC aún no se ha corregido.
