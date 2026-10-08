# Didit · estados y recuperación de identidad (2026-10-08)

## Incidencias reproducidas
- El segundo toque en **Verificar identidad** con un intento sin terminar daba HTTP 500 / PostgreSQL `23505` por `identity_verifications_provider_session_uidx`. Didit devuelve la **misma sesión** si el `workflow_id` + `vendor_data` todavía tienen una sesión abierta; Express intentaba insertar esa sesión otra vez.
- El SDK a veces entrega `VerificationFailed` aunque Didit ya cambió el estado a `In Review`. La app mostraba el toast genérico «No se pudo completar» sin refrescar el resultado.
- La interfaz permitía «Verificar nuevamente» incluso tras una identidad verificada o rechazada.
- La integración trataba `Expired` como identidad rechazada en vez de una sesión incompleta.

## Contrato del servidor
1. Crear sesión solo para usuario autenticado y país/zona habilitados.
2. `create`: para `review`, `rejected` y `verified`, devolver estado bloqueado, no generar otra sesión. En un caso no concluido, obtener el token efímero de Didit; si `provider_session_id` ya existe y pertenece **al mismo usuario y entorno**, reutilizarlo sin INSERT. Un usuario distinto jamás puede apropiarse de esa sesión. Capturar conflictos concurrentes `23505` únicamente para la misma identidad/sesión y estado recuperable.
3. `refresh` y webhooks deben reflejar `Approved → verified`, `Declined → rejected`, `In Review → review`, `Resubmitted/Not Started/In Progress → processing`. `Expired/Abandoned/Kyc Expired` no es `Declined`: conservar motivo en `provider_status` y permitir iniciar un nuevo intento cuando corresponda.
4. Registrar `result.modules` sin almacenar imágenes ni videos nuevos, para explicar si falló la prueba de vida.
5. La verificación se evalúa **siempre en backend**. Ninguna interacción Flutter concede `verified` ni acceso de conductor.

## Experiencia de usuario
- **Pendiente/no iniciada**: «Continuar verificación» vuelve a abrir el intento, sin nuevo registro.
- **Reenviada (Resubmitted)**: «Reintentar verificación» reabre la misma sesión y Didit indica qué pasos repetir. Si falló vida, conservar el carné cuando Didit lo permita.
- **En revisión (In Review)**: mostrar motivo seguro, «Actualizar estado» y «Contactar soporte»; *no* falsificar `Resubmitted` ni permitir esquivar revisión. Soporte/Didit debe autorizar el reenvío de módulos.
- **Rechazada (Declined)**: pantalla bloqueada del registro, ayuda y consulta de estado. No autorizar trabajo como conductor.
- **Aprobada**: ocultar opción de crear otra verificación.
- **Falla del SDK/red**: refrescar backend antes de mostrar error; no confundir error de cámara con rechazo de documentos.

## Matriz de QA pendiente en teléfono real
1. Usuario sin sesión: `create` → SDK nativo y una sola fila.
2. Mismo usuario no terminó: segundo `create` devuelve `reused:true`, mismo session_id, sin HTTP 500 ni INSERT; el SDK abre cámara.
3. Otro usuario: genera session_id propio; si Didit devuelve uno ajeno, bloquear con `session_owner_conflict`.
4. Liveness fallido y document/face aprobados: revisión con soporte, nunca «fallo de red». El reintento de *solo* liveness requiere un `Resubmitted` real de Didit.
5. Decisión de rechazo: pantalla bloqueada sin botón de nueva sesión; acceso al soporte.
6. `Resubmitted`: botón de reintento; `Approved`: cuenta habilitada desde servidor.
7. Cierre/reingreso y error de red mientras está en revisión: conservar estado, mostrar mecanismo de refresco.
8. La ruta Preview y Producción mantienen secretos, datos y webhooks separados.

El hotfix no autoriza publicar Android, no cambia firmas ni build number de Play; requiere compilar una nueva versión Android después de verificar Flutter y backend en CI.
