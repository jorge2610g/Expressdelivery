# REVIEW — Flujo completo de Express (Preview y Producción) · 2026-10-10

- **Alcance:** pasajero, conductor, admin y socio/aliado, en Preview y Producción.
- **Tipo:** revisión parcial. Claude no programa (CLAUDE.md): no se modificó código, SQL, Edge Functions, despliegues ni permisos.
- **Rama de la documentación:** `claude/express-admin-audit-cp07ml`.

## Veredicto
**No es posible confirmar que "todo esté bien" en Producción ni en Preview.** Desde el entorno de revisión no se puede abrir `admin.expressviajes.online` (ni `/` ni `/preview/` responden desde el sandbox, HTTP 000) y no hay credenciales de prueba. Lo que sí se puede afirmar es lo que consta en evidencia (sección 1), lo que el código confirma como fallo (sección 2) y qué debe probar el propietario (sección 4).

## 1. Verificado con evidencia

| Área | Qué se revisó | Resultado |
|---|---|---|
| Despliegue web | Workflow `deploy-web.yml` (runs 185–188) | Success. |
| Seguridad BD (proyecto `zgpijrznvaskgcmauwxx`, solo lectura) | `get_advisors` tipo security | Sin ERROR. WARN: 11 funciones `SECURITY DEFINER` ejecutables por `anon`; 374 ejecutables por `authenticated`; protección de contraseñas filtradas en Auth **deshabilitada**. |
| Rendimiento BD (solo lectura) | `get_advisors` tipo performance | INFO: 32 claves foráneas sin índice; 54 índices sin uso. WARN: 8 casos de `multiple_permissive_policies` (tablas `driver_subscription_*`, `dynamic_pricing_*`). |
| Migraciones de auditoría | E1, E1b, E4, E6 | Aplicadas en QA y Producción según `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md`. E4 (aprobación automática del conductor) se reemplaza por activación manual en #154. |
| Pasajero: flecha atrás sobre ofertas | Código `lib/video_style_home.dart` ~5233-5246 | **Confirmado** (ver hallazgo P1). |
| Pasajero: "Viajes programados" | Código `_showPassengerMenu()` ~4295-4330, `connected_experience.dart` | **Confirmado** (ver hallazgo P2). |
| Conductor: zona que desaparece | Trigger `set_driver_zone_from_location` | Causa raíz identificada; corrección en #154 (pendiente de QA y de Producción). |
| Conductor: error técnico al perder red | `expressFriendlyLoadError` en #150 (`f053e36`) | Código aprobado (REVIEW-150-r5). Falta prueba manual en Preview. |
| Admin: activar conductor | #154 + Adminexpress #57 | **No aprobado** (REVIEW-154-57). |
| Admin: rediseño visual | Adminexpress #60–#63 | Abiertos y sin fusionar. #63 es el de 99 archivos. Versión desplegada en `/preview/` no verificada. |

## 2. Hallazgos del flujo (confirmados en código)

| ID | Flujo | Hallazgo | Estado / siguiente paso |
|---|---|---|---|
| P1 | Pasajero · ofertas | Aparecen dos botones de regreso en la misma esquina: "Cancelar solicitud" y la flecha circular. Se superponen. | Spec `SPEC-2026-10-10-passenger-offer-back-and-scheduled-menu.md`, tarea 1. Pendiente de implementar. |
| P2 | Pasajero · menú | "Mis servicios" y "Viajes programados" llaman el mismo `onHistory()`; el historial no tiene filtro de programados. | Spec anterior, tarea 2. Pendiente de implementar. |
| P3 | Pasajero · menú | `_CustomerActivity` tiene un filtro "Programados" pero no se usa (código muerto). | Se elimina solo si queda sin uso tras P2. |
| D1 | Conductor · zona | La zona se borraba al actualizar ubicación sin GPS. | #154 (migración) pendiente de QA y de autorización para Producción. La reparación de datos es manual y requiere autorización. |
| D2 | Conductor · red | Al perder red, el panel mostraba un error técnico y no se recuperaba. | #150 (código aprobado). Falta la prueba manual. |
| D3 | Conductor · carga | El panel recargaba con demasiada frecuencia. | #150 (coordinador de refresco). Falta la prueba manual. |
| A1 | Admin · activación | Conductores aprobados sin zona no podían activarse. | #154 + #57 (no aprobado: faltan pruebas QA 3–9 y changelog). |
| A2 | Admin · KYC manual | Las notificaciones salían también al aprobar, no solo al rechazar. | #154 notifica solo al rechazar. Pendiente de QA. |
| A3 | Admin · Preview | Tras desplegar, el panel de Preview puede no reflejar el rediseño (caché, URL sin `/preview/`, o SHA de despliegue distinto). | No verificado. Ver checklist. |
| S1 | Seguridad BD | 374 funciones `SECURITY DEFINER` ejecutables por `authenticated` y 11 por `anon`. Algunas pueden ser intencionales (RPC que validan `auth.uid()` internamente), otras no. | Requiere inventario y clasificación (sección 5, tarea 1). No se cambia nada sin spec. |
| S2 | Seguridad Auth | Protección de contraseñas filtradas deshabilitada. | Decisión del propietario en el panel de Supabase. |

## 3. No verificado (y por qué)
- Ninguna pantalla real de pasajero, conductor, admin ni socio: el sandbox no llega al dominio de admin y no hay sesión.
- Preview y Producción no se compararon en UI. Solo se revisó el estado de las ramas y los despliegues.
- La APK temporal (`native-qa`) no se descargó: el proxy bloquea el almacenamiento del artefacto. Vence el 2026-10-11 13:09 UTC (run 38053815059).
- Los casos QA 3–9 de #154 requieren ejecución en QA con transacciones y rollback. No se han ejecutado.

## 4. Checklist manual para el propietario

Anotar para cada punto: OK / FALLA, captura y entorno (Preview o Producción). Usar cuentas de prueba, no datos reales de clientes.

**Admin (`admin.expressviajes.online/` y `/preview/`)**
1. Borrar caché o abrir en ventana privada. Entrar a `/preview/`. Confirmar el banner de Preview.
2. Inicio de sesión con correo y contraseña. Cerrar sesión y volver a entrar.
3. Inicio con Google en Preview: debe volver a `/preview/` (confirmar que la Redirect URL está configurada).
4. Panel principal: los contadores cargan y no muestran error.
5. Conductores: abrir uno con documentos pendientes. Ver fotos, aprobar y rechazar en cuenta de prueba. Revisar que el rechazo notifica.
6. Conductores sin zona: el selector de zona aparece y el botón "Activar conductor" se habilita solo con fotos aprobadas y documento verificado (#57, solo cuando esté aprobado).
7. Viajes: lista, filtros, detalle, cancelación de prueba.
8. Operación en vivo / mapa: carga sin errores.
9. Socios y aliados: abrir el panel y revisar listado y detalle.
10. Anotar qué panel se ve (rediseño o versión anterior) y la hora.

**Pasajero (Preview con cuenta de prueba)**
1. Pedir un viaje. Esperar una oferta: confirmar que **no** aparece la flecha atrás sobre "Cancelar solicitud" (P1).
2. Cancelar desde la oferta: vuelve al panel principal.
3. Menú → "Mis servicios": abre el historial en "Todos".
4. Menú → "Viajes programados": hoy abre lo mismo que "Mis servicios" (P2). Anotar.
5. Programar un viaje (si la función está activa) y revisar que aparece en historial.

**Conductor (Preview, cuenta de prueba en línea en la misma zona)**
1. Con el conductor en línea 60 s sin hacer nada: no debe haber más de 5 cargas completas ni parpadeo (D3).
2. Pedir viaje desde el pasajero: el conductor lo ve en 2 s o menos (C).
3. El pasajero cancela: el conductor deja de verlo en 3 s o menos (D1).
4. Aceptar y ver el viaje activo sin que vuelva a aparecer la solicitud (D2).
5. Modo avión 5 s después de aceptar o completar: sin error técnico ni URL; se recupera al volver la red (D2).
6. Revisar que la zona del conductor no se borra al mover la ubicación (D1, solo si #154 ya está en Preview).

**Producción (solo lectura; no probar con datos reales)**
1. Login admin con la cuenta original.
2. Dashboard y listas cargan.
3. Conductores: abrir uno sin cambiar nada.
4. Confirmar que la versión de Producción no tiene el banner de Preview.

## 5. Siguiente trabajo (para la IA programadora)

Ninguna de estas tareas cambia código de la app ni datos. Son inventarios y pruebas.

1. **S1 · Inventario de funciones `SECURITY DEFINER`:** clasificar las 11 ejecutables por `anon` y las 374 por `authenticated` en: (a) intencionales, con `auth.uid()` o validación de admin interna; (b) sin validación; (c) de sistema, que no deberían ser RPC públicas. Entregar tabla con nombre, esquema, grants y motivo. Sin cambios.
2. **Pruebas pendientes de #154:** casos 3–9 de `docs/specs/SPEC-2026-10-10-driver-zone-kyc-activation.md`, según `REVIEW-154-57-driver-zone-kyc-2026-10-10.md`.
3. **Pruebas pendientes de #150:** checklist A/C/D1/D2/Red de `REVIEW-150-2026-10-10-r5.md`.
4. **Specs de pasajero (P1, P2, P3):** ya escritas; implementar en rama nueva desde `main`.

---

## PROMPT PARA LA IA PROGRAMADORA

Repo `jorge2610g/Expressdelivery`. Rama de trabajo: `claude/express-admin-audit-cp07ml`. Lee `docs/reviews/REVIEW-flujo-completo-2026-10-10.md`.

Tarea única de **solo lectura** (no cambies código, SQL, migraciones, permisos ni datos; no apliques nada en Producción):

1. Usando el MCP de Supabase sobre el proyecto `zgpijrznvaskgcmauwxx` (solo `SELECT` sobre `pg_proc`, `information_schema.routine_privileges` y `pg_policies`), lista:
   - las funciones `SECURITY DEFINER` ejecutables por `anon`;
   - las ejecutables por `authenticated` (374 según el advisor).
2. Para cada una, indica: esquema, nombre, firma, grants, si valida `auth.uid()` o `is_admin` dentro del cuerpo, y si es de uso público (app) o de sistema (trigger, cron, Edge Function).
3. Clasifica en (a) intencional y validada, (b) sin validación aparente, (c) debería ser solo `service_role`.
4. Entrega un archivo `docs/reviews/INVENTARIO-security-definer-2026-10-10.md` con la tabla y el conteo por categoría. Incluye la consulta SQL exacta que usaste.
5. No propongas migraciones todavía: solo la lista. Claude revisará y escribirá la spec de corrección.

Formato de devolución: `docs/AI_RESPONSE_FORMAT.md`. Haz commit solo con el archivo nuevo en `claude/express-admin-audit-cp07ml`. No abras PR ni fusiones salvo que el propietario lo pida.
