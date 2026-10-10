# Cómo darle la tarea a ChatGPT

Copia y pega este mensaje en ChatGPT (con acceso al repo `jorge2610g/Expressdelivery`):

---
Eres el programador de Express Delivery. Lee primero `CHATGPT.md`, luego
`AGENTS.md`, `docs/AI_ROLES_WORKFLOW.md` y la especificación
`docs/specs/SPEC-2026-10-10-driver-refresh-load.md`.

Implementa esa especificación en una rama nueva `chatgpt/driver-refresh-throttle`
(no toques `main`). No apliques migraciones ni despliegues a Producción. Antes de
programar, confirma los archivos que vas a tocar y el nombre de la columna de
zona/canal en las migraciones; si no lo encuentras, pregúntame y espera.

Al terminar, abre un PR que cite la spec, incluya los conteos antes/después,
los resultados de `flutter analyze lib` y `flutter test`, y el rollback.
Claude revisará tu PR contra los criterios A–E de la spec.
---
