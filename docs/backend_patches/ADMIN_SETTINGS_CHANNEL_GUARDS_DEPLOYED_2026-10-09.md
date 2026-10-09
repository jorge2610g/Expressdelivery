# Express — control de autorización de canal en ajustes administrativos

Fecha: **2026-10-09**. Cambio **ya aplicado** a Supabase principal
`zgpijrznvaskgcmauwxx` como migración **20261009233719** y validado
primero en el proyecto físico QA `xbphilqezmwfjfpdbwad`.

## Problema

Tres RPC privilegiadas validaban `public.is_admin()`, pero no validaban
si el administrador tenía acceso al canal solicitado por `p_channel`.
Por ejemplo, un administrador autorizado solo en Preview podía enviar
`p_channel='production'` para cambiar ajustes reales de Producción.

RPC corregidas:

| Función | Configuración sensible |
| --- | --- |
| `admin_driver_kyc_bolivia_set_method` | Método de verificación manual/automático por canal |
| `admin_update_driver_priority_settings_v2` | Prioridad/asignación de conductores por canal |
| `admin_update_dynamic_pricing_settings` | Parámetros de demanda y multiplicadores por canal |

Se añadió únicamente:
```sql
if not public.admin_environment_allowed(v_channel) then
  raise exception 'No autorizado para modificar este entorno';
end if;
```
**después** del chequeo administrativo/canal y **antes** de escribir
configuración. Se mantuvieron firmas, defaults, SQL operativo, SECURITY
DEFINER y grants. Un administrador autorizado en Producción conserva
su capacidad actual de administración. No se activó DIDIT, SMS ni
una pasarela de pago.

## Evidencia reproducible

- Respaldo literal de las tres definiciones anteriores:
  `docs/backend_patches/rollback_admin_settings_channel_grants_20261009.sql`.
- SQL candidato probado en QA:
  `docs/backend_patches/qa_admin_settings_channel_grants_20261009.sql`.
- Migración histórica real aplicada:
  `supabase/migrations/20261009233719_admin_settings_explicit_channel_privileges_20261009.sql`.
- En QA físico se verificó con superadmin **Preview-only** bajo
  `SET LOCAL ROLE authenticated`, dentro de transacciones terminadas en
  `ROLLBACK`:
  - Las tres llamadas con `p_channel='production'` fueron **rechazadas**.
  - Las tres llamadas con `p_channel='preview'` tuvieron resultado válido.
- Antes de migrar se comparó el cuerpo de `pg_get_functiondef` de cada
  RPC: tras quitar solo el nuevo guard, la función QA candidata fue
  semánticamente igual al código real de Producción.
- Después de migrar, `pg_proc` confirmó los tres guards, la firma y
  privilegios `authenticated` originales, y que siguieron en modo
  `SECURITY DEFINER`.
- Huellas MD5 JSON + conteos **idénticos antes/después** en cinco tablas:
  `admin_environment_config` (25),
  `driver_kyc_method_settings` (2),
  `driver_priority_settings` (1),
  `dynamic_pricing_channel_settings` (2) y
  `dynamic_pricing_settings` (1).
- CI de este PR compara cada cuerpo SQL con el backup tras quitar
  exclusivamente el guard; falla ante cualquier deriva adicional.

## Límites importantes

**No significa aislamiento backend completo.** El mismo `super_admin`
del Supabase principal todavía puede tener permiso para ambos entornos.
Si un cliente tiene la misma credencial con ambos permisos, no se puede
verificar el origen de esa solicitud solo por el `p_channel` que
envía. Además, la auditoría estática de SQL encontró **87 posibles
escritores** `SECURITY DEFINER` del catálogo `admin_*` que carecen
de parámetro de entorno y contienen palabras de escritura; esto es un
universo de revisión, NO significa 87 vulnerabilidades confirmadas
(una función puede delegar validaciones, escribir logs o actuar sobre
datos globales permitidos). La reducción del riesgo requiere analizar
cada contrato usado por Admin web, app Android instalada, triggers y
funciones internas, y limitar privilegios por una frontera
autenticable. No revocar EXECUTE en masa sin regresión.

Las pruebas SQL realizadas aquí no reemplazan una prueba completa
Android pasajero/conductor, documentación manual, pagos, viajes,
notificaciones y regresión de usuarios existentes. No se publicó
ninguna APK/AAB o nuevo sitio web como parte de la migración.

## Plan de recuperación

Restaurar definiciones previas solo para corregir un incidente real
verificado: deshace las protecciones y reabre el acceso de un admin
con permisos exclusivos QA a otros canales. Requiere autorización y
comprobación posterior de firmas, permisos y datos. Evitar
restauraciones globales destructivas de base de datos.
