# REVIEW — Expressdelivery #154 (zona y activación) + Adminexpress #57 (botón Activar conductor)

- **Spec:** `docs/specs/SPEC-2026-10-10-driver-zone-kyc-activation.md` (incl. 3b aprobado en `86bcfa0`)
- **Expressdelivery #154:** https://github.com/jorge2610g/Expressdelivery/pull/154 · `chatgpt/driver-zone-kyc-activation` · head `d278d35`
- **Adminexpress #57:** https://github.com/jorge2610g/Adminexpress/pull/57 · `chatgpt/driver-zone-kyc-activation` · head `b1d6a29`

## Veredicto
**NO APROBADO todavía.** La lógica es correcta y cumple la spec, pero faltan las pruebas exigidas en QA (casos 3 a 9) y la documentación. Hay además 4 correcciones menores.

## Evidencia propia
### #154 (migración `20261010130655_driver_zone_kyc_activation.sql`)
- `set_driver_zone_from_location`: solo completa `zone_id` si está vacío y el punto cae en una zona; nunca la borra ni la cambia. Correcto (causa raíz resuelta).
- `admin_driver_kyc_bolivia_manual_review_part`: notifica solo en `rejected`; quita la llamada E4; devuelve `can_activate`. Mantiene `is_admin`, canal, versión optimista, historial y log. Correcto.
- `admin_driver_kyc_bolivia_manual_list`: agrega `zone_id`, `approval_status`, `zone_name` sin tocar filtros, orden ni límite. Correcto.
- `admin_driver_activate`: `is_admin`, `admin_assert_environment('production')` en Producción, `admin_assert_target_environment`, zona por prioridad (parámetro → perfil → última verificación), valida país, exige documentos verificados y todas las fotos aprobadas, actualiza perfil, notifica, registra log. `revoke … from public, anon`. Correcto.
- Respaldo `DZK:` en `admin_function_backup_20261010` y rollback que restaura las 3 funciones y borra la nueva. Correcto.
- Reparación `docs/ops/20261010_repair_driver_zone.sql`: manual, antes/después, solo `zone_id is null`, mismo país. Correcto.
- Requisitos activos en Producción hoy: BO `identity_card`; CL `driver_license` e `identity_card` (ninguno global).
- CI: `validate` y `change-inventory` en verde.
- La descripción del PR reconoce: "Los casos QA que requieren admin allow_production quedan pendientes".

### #57 (`lib/admin_bolivia_kyc.dart`)
- Carga zonas del país (`admin_zone_list_for_country`), selector `Zona del conductor` cuando falta zona, botón `Activar conductor` deshabilitado hasta que todas las fotos estén aprobadas y el documento verificado, confirmación, llamada a `admin_driver_activate`, snacks, chip `Activo · <zona>` y estado `verified → Verificada`. Correcto.
- Los conductores ya aprobados pero sin zona (`eb10e736`, `e3656702`) muestran el botón con selector, que es lo que corresponde.
- CI: `validate` en verde. No hay test nuevo ni capturas.

## Hallazgos
### Bloqueantes
- **B1 · Pruebas QA incompletas.** Faltan los casos 3–9 de la sección 7 (notificaciones por estado, `can_activate`, errores y éxito de `admin_driver_activate`, permisos de admin sin Producción, rollback y campos nuevos de la lista). Que QA no tenga un admin con `allow_production` no impide probar: dentro de una transacción con `rollback`, insertar un `admin_users` temporal (o actualizar uno de QA) con `allow_production=true`, fijar `request.jwt.claims` con su `sub` y `set local role authenticated`, como en las pruebas E1/E6 (`docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md` §5). Entregar salida literal de cada caso.
- **B2 · Documentación.** Ningún PR actualiza `docs/CHANGELOG_ACTIVE.md`. Agregar entrada 2026-10-10 en ambos repos: causa raíz (trigger), funciones cambiadas, RPC nueva, cambio de E4 (activación manual), notificaciones solo al rechazar, y que la reparación de datos es manual y requiere autorización.

### No bloqueantes (corregir en el mismo push)
- **N1 · Requisitos globales.** En `admin_driver_activate`, el conteo usa `upper(r.country_code) = upper(v_profile.country_code)` y omite requisitos con `country_code is null`, a diferencia del registro (`r.country_code is null or …`). Hoy no hay requisitos globales, pero alinear: `(r.country_code is null or upper(r.country_code) = upper(v_profile.country_code))`.
- **N2 · Canal normalizado.** Usar una variable `v_channel := lower(trim(coalesce(p_channel,'')))` y emplearla en todas las llamadas (hoy se mezcla `lower(p_channel)` sin `trim`).
- **N3 · Doble activación.** En el diálogo, `_busy` vive en el estado externo y el `StatefulBuilder` no se reconstruye: el botón puede pulsarse dos veces y enviar dos notificaciones. Llevar un `busy` local del diálogo (o deshabilitar con `setDialogState`) mientras corre la RPC.
- **N4 · Texto obsoleto.** El diálogo sigue diciendo "La aprobación del conductor y del vehículo es independiente de estas fotografías." Con la activación manual cambiarlo por: "Al activar, el conductor queda aprobado en la zona elegida y podrá recibir solicitudes."

## Nota para el propietario
- El conductor `e3656702` ("Jorge luis", carné 10804108) tiene la **foto de perfil rechazada** ("fotos inadecuedas"). Con la regla nueva no se podrá activar hasta aprobarla o que la reemplace.
- Orden de aplicación cuando esté aprobado: QA (ya) → su autorización → Producción → panel #57 → reparación de datos (otra autorización).

---

## PROMPT PARA LA IA PROGRAMADORA

Lee `docs/reviews/REVIEW-154-57-driver-zone-kyc-2026-10-10.md` (repo `jorge2610g/Expressdelivery`, rama `claude/express-admin-audit-cp07ml`).

1. **B1:** ejecuta en QA `xbphilqezmwfjfpdbwad` los casos 3 a 9 de la sección 7 de `docs/specs/SPEC-2026-10-10-driver-zone-kyc-activation.md`, cada uno dentro de una transacción con `rollback`. Para el admin con Producción, crea o actualiza dentro de la transacción un `admin_users` con `allow_production=true`, fija `request.jwt.claims` con su `sub` y usa `set local role authenticated` (patrón de `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md` §5). Prueba también el rollback (0 diferencias). Entrega la salida literal de cada caso.
2. **B2:** agrega una entrada 2026-10-10 en `docs/CHANGELOG_ACTIVE.md` en los dos repos (contenido indicado en la revisión).
3. **N1 y N2** en una migración nueva si la anterior ya se aplicó en QA, o en la misma si aún no se fusionó y reaplicas en QA (indícalo):
   - incluir requisitos con `country_code is null`;
   - usar `v_channel` normalizado en todo `admin_driver_activate`.
4. **N3 y N4** en `lib/admin_bolivia_kyc.dart`: `busy` local del diálogo y el texto nuevo.
5. `flutter analyze` y `flutter test` en Adminexpress; capturas del diálogo con el botón deshabilitado y habilitado.

No apliques nada en Producción, no ejecutes la reparación de datos y no fusiones. Devuelve el resultado con el formato de `docs/AI_RESPONSE_FORMAT.md`.
