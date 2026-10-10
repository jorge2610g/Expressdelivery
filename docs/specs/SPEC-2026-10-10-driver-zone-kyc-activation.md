# SPEC 2026-10-10 — Zona del conductor, notificaciones de verificación y botón "Activar conductor"

**Estado:** lista para la IA programadora. Claude revisa después.
**Repos:** `jorge2610g/Expressdelivery` (migración SQL) y `jorge2610g/Adminexpress` (botón y textos del panel).
**Flujo obligatorio de base de datos:** probar en QA (`xbphilqezmwfjfpdbwad`) → el propietario autoriza → aplicar en Producción (`zgpijrznvaskgcmauwxx`). Nada se aplica en Producción sin esa autorización.

## 1. Problema reportado (propietario, 2026-10-10)
1. Aprobó las 3 fotos de un conductor de Trinidad y el panel Producción → Conductores → Bolivia / Trinidad dice "Todavía no hay conductores registrados".
2. Recibe notificación el conductor también cuando una foto se aprueba; solo debe recibirla cuando una foto se rechaza (para volver a cargarla).
3. Quiere un botón **"Activar conductor"** cuando las fotos estén aprobadas, y que el conductor aparezca en la lista de su zona.

## 2. Evidencia (consultas de solo lectura en Producción, 2026-10-10)

### 2.1 La lista filtra por `zone_id` y los conductores de Bolivia lo tienen vacío
- El panel llama `admin_driver_list_v3(p_channel, p_zone_id)` (`Adminexpress lib/admin_panel.dart:382-389`), que filtra `where d.zone_id = v_zone`.
- Conteo de `driver_profiles` por zona: **5 conductores con `zone_id = null`** (2 aprobados, 3 pendientes); Trinidad 1; Iquique 3.
- Ejemplo: `eb10e736-…` "Jorge luis Carrillo alvarez" (el que se aprobó hoy): `country_code = BO`, `city = Trinidad`, **`zone_id = null`**, `approval_status = approved`. Su `identity_verifications` (12:37) guarda `zone_id = a6a6b163-…` (Trinidad). Igual `e3656702-…`, `f2307df5-…` (Luis Fernando Alvarez galles), `c787db2e-…`.
- Es decir: el registro **sí** eligió Trinidad, pero el `zone_id` del perfil se borró después.

### 2.2 Causa raíz: el trigger de ubicación borra la zona
`driver_profiles` tiene `trg_driver_zone_from_location BEFORE INSERT OR UPDATE OF latitude, longitude` → `set_driver_zone_from_location()`:
```sql
if new.latitude is not null and new.longitude is not null then
  v_zone := public.service_zone_id_for_point(new.latitude,new.longitude);
  new.zone_id := v_zone;              -- fuera de cobertura => null
  ...
else
  new.zone_id := null;                -- sin GPS => borra la zona
end if;
```
- `submit_driver_onboarding*` inserta el perfil **sin coordenadas** y con `zone_id = <zona elegida>`; el trigger de `INSERT` lo pone en `null`.
- Además, cada actualización de GPS reemplaza la zona registrada por la del punto (y por `null` si el punto cae fuera de cobertura). La zona operativa no debe depender del GPS en vivo.
- **Impacto mayor que la lista del panel:** un conductor sin `zone_id` no tiene Realtime de solicitudes (PR #150 filtra por `zone_id`) y no entra en la oferta por zona. Hoy esos conductores aprobados no pueden recibir viajes.

### 2.3 Notificaciones al revisar fotos
`admin_driver_kyc_bolivia_manual_review_part(...)` inserta en `public.notifications` en **todos** los cambios: `rejected` ("Corrige una fotografía"), `approved` ("Fotografía aprobada") y `pending` ("Fotografía reactivada"). El push sale de esa inserción.

### 2.4 Aprobación actual
La misma función llama `driver_auto_approve_if_complete(...)` (marcador `E4-20261010`): el conductor pasa a `approved` sola apenas todos los documentos obligatorios quedan verificados. Por eso `eb10e736` ya figura `approved`, pero sin zona no aparece en la lista.

## 3. Decisión de diseño (por pedido del propietario)
- La activación pasa a ser **manual** con el botón "Activar conductor". La aprobación automática E4 deja de ejecutarse desde la revisión de fotos (se conserva el helper, no se borra).
- La zona del perfil es la **zona registrada** (la que eligió en el registro o la que asigne el admin). El GPS ya no la borra ni la cambia; el cambio de zona sigue por `request_my_driver_zone_change`.

## 4. Tarea A — Migración SQL (repo Expressdelivery, rama nueva desde `main`)
Archivo nuevo: `supabase/migrations/2026101020xxxx_driver_zone_kyc_activation.sql`, con respaldo de definiciones previas en una tabla de respaldo (patrón de E1/E4) y rollback en `docs/backups/20261010_driver_zone_kyc_rollback.sql`.

1. **`set_driver_zone_from_location()`**: nunca asignar `null`. Si hay coordenadas y `new.zone_id` es `null`, completar con `service_zone_id_for_point(...)` (solo si devuelve una zona). Si `new.zone_id` ya tiene valor, no tocarlo. Sin coordenadas: no tocar `zone_id`.
2. **`admin_driver_kyc_bolivia_manual_review_part(...)`**:
   - Insertar en `notifications` **solo** cuando `v_status = 'rejected'` (mismo título, cuerpo y metadata actuales). Para `approved` y `pending`: no insertar nada.
   - Quitar la llamada `driver_auto_approve_if_complete(...)` (marcador E4) y devolver en su lugar `'can_activate', <booleano>` = todas las partes con foto (`front`, `back`, `selfie` y `profile` si existe) en `approved` **y** el documento en `verified`.
3. **Nueva RPC `admin_driver_activate(p_driver_id uuid, p_zone_id uuid default null, p_channel text default 'production')`**, `SECURITY DEFINER`, `search_path public`:
   - `is_admin()` y `admin_assert_target_environment(p_driver_id, p_channel)`; además el patrón de guard de Producción (`admin_assert_environment('production')` cuando `p_channel = 'production'`).
   - Exigir que todos los documentos obligatorios del conductor estén `verified` y que, en el documento de identidad manual, todas las partes con foto estén `approved`. Si no: `raise exception 'Faltan fotografías por aprobar'`.
   - Zona: `coalesce(p_zone_id, driver_profiles.zone_id, zona de la última identity_verifications express_manual (result->>'zone_id'))`. Validar que exista en `service_zones` y que su `country_code` coincida con `driver_profiles.country_code`. Si no hay zona: `raise exception 'Selecciona la zona del conductor'`.
   - `update driver_profiles set approval_status='approved', zone_id=<zona>, city=coalesce(service_zones.city, name), updated_at=now()`.
   - Notificación al conductor **solo de activación**: título `Cuenta de conductor activada`, cuerpo `Ya puedes conectarte y recibir solicitudes en <ciudad>.`, `type='driver_activation'`, `channel=p_channel`. (Si el propietario prefiere sin notificación, se quita esta línea; ver §8.)
   - `admin_log_action('driver_activate','driver_profile', p_driver_id::text, jsonb_build_object('zone_id',…, 'channel',…))`.
   - `revoke execute … from public, anon; grant execute … to authenticated`.
3b. **Ampliar `admin_driver_kyc_bolivia_manual_list(p_channel, p_limit)`** (aclaración aprobada por Claude 2026-10-10, a pedido de la IA programadora): en la misma migración nueva, con respaldo de la definición previa y rollback, agregar a cada fila `p.zone_id`, `p.approval_status` y `z.name as zone_name` (`left join public.service_zones z on z.id = p.zone_id`). Cambio **solo aditivo**: no quitar, renombrar ni reordenar campos existentes, no cambiar filtros, orden, límite, `is_admin()` ni el aislamiento por canal. Con eso el panel decide si mostrar el selector `Zona del conductor`, si deshabilitar el botón y qué chip `Activo · <zona>` mostrar.
4. **Reparación de datos (separada, en el mismo PR pero como script en `docs/ops/20261010_repair_driver_zone.sql`, NO como migración automática):** para conductores con `zone_id is null`, asignar la `zone_id` de su última `identity_verifications` (`provider='express_manual'`, `result->>'zone_id'` válida y del mismo país). Debe imprimir antes/después. Se ejecuta en Producción solo con autorización explícita del propietario.

## 5. Tarea B — Panel Admin (repo Adminexpress, rama nueva desde `main`)
Archivo: `lib/admin_bolivia_kyc.dart` (diálogo "Revisión individual de identidad").
1. Debajo de las tres fotografías, botón **`Activar conductor`** (`FilledButton.icon`, icono `Icons.verified_user_rounded`):
   - Habilitado solo si todas las partes con foto están `approved` y el conductor no está ya activo con zona. Deshabilitado con texto de ayuda `Aprueba todas las fotografías para activar.`
   - Si el conductor no tiene zona registrada, mostrar antes un `DropdownButtonFormField` `Zona del conductor` con las zonas del país del conductor (`admin_zone_list_for_country`).
   - Confirmación: título `Activar conductor`, cuerpo `<nombre> quedará aprobado en <zona> y podrá conectarse para recibir solicitudes.`, acciones `Cancelar` / `Activar`.
   - Llama `admin_driver_activate(p_driver_id, p_zone_id, p_channel)`. Éxito: snack `Conductor activado en <zona>.`, cerrar diálogo y recargar. Error: snack `No se pudo activar: <mensaje>`.
2. Textos de estado traducidos en la lista (hoy salen en inglés): `verified` → `Verificada`, `pending` → `Pendiente`, `rejected` → `Rechazada`.
3. Fila de la lista: si el conductor ya está activo, mostrar chip `Activo · <zona>`.

## 6. Restricciones
- No editar migraciones existentes; todo cambio en una migración nueva con respaldo y rollback.
- No aplicar nada en Producción ni ejecutar la reparación de datos sin autorización del propietario.
- No cambiar `driver_auto_approve_if_complete` (solo dejar de llamarlo desde la revisión de fotos).
- No tocar Edge Functions.
- Mantener el aislamiento Preview/Producción (`p_channel`, `admin_assert_target_environment`).

## 7. Cómo probar (en QA `xbphilqezmwfjfpdbwad`, dentro de transacción cuando aplique)
1. Insertar un perfil de conductor sin coordenadas con `zone_id` = Trinidad → `zone_id` se conserva.
2. Actualizar lat/lng a un punto fuera de cobertura → `zone_id` se conserva; con `zone_id` null y punto dentro de Trinidad → se completa con Trinidad.
3. Revisar una foto `approved` → 0 filas nuevas en `notifications`; `rejected` → 1 fila; `pending` → 0.
4. Revisar las 3 fotos `approved` → el conductor sigue `pending` (sin auto-aprobación) y la respuesta trae `can_activate = true`.
5. `admin_driver_activate` con una foto pendiente → error `Faltan fotografías por aprobar`; con todo aprobado → `approved` + zona; aparece en `admin_driver_list_v3('production', <zona>)`.
6. Como `anon` → sin permiso de ejecutar la RPC. Admin sin `allow_production` en canal production → error de entorno.
7. Rollback probado en QA: 0 diferencias.
8. `admin_driver_kyc_bolivia_manual_list('production', 150)` en QA devuelve los mismos campos que antes más `zone_id`, `approval_status`, `zone_name`; mismo número de filas y mismo orden que la versión previa.
9. Panel: `flutter analyze` sin errores fatales, `flutter test` en verde; capturas del diálogo con el botón deshabilitado y habilitado.

## 8. Decisiones abiertas para el propietario (no bloquean la tarea)
- ¿Notificación al activar? Por defecto **sí** ("Cuenta de conductor activada"). Si no la quiere, se elimina esa línea.
- Reparación de los 5 perfiles sin zona: requiere su autorización para ejecutarla en Producción.

## Formato de devolución
`docs/AI_RESPONSE_FORMAT.md`: commits y PRs (uno por repo), archivos, salida de las pruebas en QA (antes/después), salida de analyze/test, capturas, y el texto exacto de la reparación de datos para que el propietario la autorice.

---

## PROMPT PARA LA IA PROGRAMADORA

Lee `docs/specs/SPEC-2026-10-10-driver-zone-kyc-activation.md` (repo `jorge2610g/Expressdelivery`, rama `claude/express-admin-audit-cp07ml`) completa y ejecútala tal cual:
- **Tarea A** en `jorge2610g/Expressdelivery`, rama nueva desde `main` (p. ej. `chatgpt/driver-zone-kyc-activation`): una migración nueva con respaldo y rollback que (1) impide que `set_driver_zone_from_location` borre o cambie la zona registrada, (2) hace que `admin_driver_kyc_bolivia_manual_review_part` solo notifique en `rejected`, quita la auto-aprobación desde la revisión de fotos y devuelve `can_activate`, y (3) crea la RPC `admin_driver_activate`. Además, el script de reparación de datos en `docs/ops/` (no se ejecuta solo).
- **Tarea B** en `jorge2610g/Adminexpress`, rama nueva desde `main`: botón "Activar conductor" en el diálogo de revisión de identidad, selector de zona cuando falte, confirmación, snacks y estados traducidos.

Prueba todo primero en el proyecto QA `xbphilqezmwfjfpdbwad` con los 9 casos de la sección 7. **No apliques nada en Producción (`zgpijrznvaskgcmauwxx`) ni ejecutes la reparación de datos sin autorización explícita del propietario.** No edites migraciones existentes, no toques Edge Functions, no fusiones. Si algo de la spec no es claro, detente y pregunta.

Devuelve el resultado con el formato de `docs/AI_RESPONSE_FORMAT.md`.
