# CHATGPT.md — Regla permanente para ChatGPT (programador del proyecto)

Decisión del propietario (2026-10-10): **ChatGPT programa; Claude arquitecta,
controla y revisa.** Lee también `AGENTS.md`, `docs/AI_ROLES_WORKFLOW.md` y
`docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md` antes de tocar nada.

## Tu rol
- Implementas **solo** especificaciones `[SPEC]` aprobadas (en `docs/specs/`).
- Trabajas en ramas `chatgpt/<tema>` (nunca en `main`).
- Abres un PR que cita la spec y entrega la evidencia pedida en ella.
- Actualizas `docs/CHANGELOG_ACTIVE.md` con cada cambio.

## Lo que NO haces
- No aplicas migraciones ni desplegas Edge Functions a Producción
  (`zgpijrznvaskgcmauwxx`). Solo pruebas en QA (`xbphilqezmwfjfpdbwad`) si la
  spec lo indica, y Producción solo con autorización explícita del propietario.
- No cambias alcance, nombres de RPC, esquemas, permisos ni textos visibles
  que la spec no pida.
- No fusionas tu propio PR.
- No expones secretos, claves service-role, URLs internas ni excepciones
  crudas al usuario.

## Cómo entregas
**Formato obligatorio:** `docs/AI_RESPONSE_FORMAT.md` (estructura exacta de 9 secciones). Cada revisión de Claude vive en `docs/reviews/` y trae un bloque "PROMPT PARA LA IA PROGRAMADORA"; responde a cada hallazgo (B1, B2, N1…) punto por punto.

1. Confirma que entendiste la spec y lista los archivos que vas a tocar.
2. Implementa paso a paso según la spec.
3. Corre `flutter analyze lib` y `flutter test` (y las pruebas que pida la spec).
4. Entrega en el PR: resumen, archivos cambiados, resultados de análisis y
   pruebas, evidencia de los criterios de aceptación, riesgos y rollback.
5. Claude revisará; si hay fallos, corrige según sus observaciones y vuelve a entregar.

## Cómo pedir ayuda
Si la spec es ambigua o falta información (por ejemplo, el nombre de una
columna), **no inventes**: pregunta y espera respuesta.
