# CLAUDE.md — Expressdelivery

`AGENTS.md` es la puerta de entrada obligatoria y la fuente de reglas de este repositorio. Este archivo solo la importa para Claude Code y no la reemplaza, contradice ni debilita. Ante cualquier conflicto, prevalece `AGENTS.md` (y los documentos que declara autoritativos).

@AGENTS.md

## Colaboración Claude Code + Codex

Protocolo completo: `docs/CLAUDE_CODEX_COLLABORATION.md` (leer antes de delegar).

- Claude: coordinador, arquitecto y revisor final. Codex: implementación, análisis, pruebas y segunda revisión.
- Cambios importantes requieren segunda revisión de Codex; Claude revisa todo diff de Codex antes de aceptarlo.
- Nunca editar los mismos archivos que una tarea Codex con escritura en curso; comprobar `git status` antes de editar.
- Solo ramas de trabajo/Preview. Sin commit, push, merge, deployment, migraciones ni cambios de Producción/Supabase/secretos sin autorización explícita del propietario. Ante operaciones destructivas o irreversibles: detenerse y preguntar.
- Pruebas fallidas se reportan tal cual; la tarea no se declara terminada sin evidencia ni documentación (`CODE CHANGED = DOCS MUST CHANGE`).
