# Colaboración Claude Code + Codex — Expressdelivery

> **Estado:** vigente desde 2026-10-10 (rama `tools/claude-codex-integration-20261009`).
> **Alcance:** solo proceso de trabajo de agentes IA. No cambia código funcional, Supabase, workflows, release gate ni Producción.
> **Jerarquía:** este documento está **subordinado** a `AGENTS.md`, al handoff maestro vigente y a `docs/DOCUMENTATION_POLICY.md`. Si algo aquí contradice esas reglas, prevalecen ellas.

## 1. Roles

| Agente | Rol |
|---|---|
| **Claude Code** | Coordinador, arquitecto y revisor final. Analiza la tarea, crea el plan, decide qué delegar, inspecciona todo cambio y entrega el resumen final al propietario. |
| **Codex** (plugin `codex@openai-codex`) | Segundo agente: implementación, análisis, pruebas y segunda revisión. Lee `AGENTS.md` y queda sujeto a las mismas reglas. |

Claude puede delegar a Codex automáticamente cuando aporte valor (implementación acotada, diagnóstico, segunda opinión, revisión). Claude sigue siendo responsable del resultado: **ningún cambio de Codex se acepta sin revisión de Claude**.

## 2. Flujo preferido

```text
Tarea del propietario
 → Claude lee AGENTS.md + handoff + docs del módulo y revisa git status
 → Claude crea el plan (Dart-only / backend / nativo, QA, docs)
 → Claude delega a Codex las partes apropiadas (archivos explícitos)
 → Codex implementa o revisa
 → Claude inspecciona el diff de Codex
 → se ejecutan las pruebas/validaciones exigidas por AGENTS.md
 → Codex hace segunda revisión en cambios importantes
 → Claude corrige o delega correcciones
 → Claude entrega resumen final
```

Resumen final obligatorio: archivos modificados, pruebas ejecutadas y su resultado real, riesgos, pendientes y si queda algún despliegue/merge/push pendiente de autorización.

## 3. Segunda revisión obligatoria

Se considera **cambio importante** (requiere revisión de Codex antes de declarar la tarea terminada) cualquier cambio que toque:

- lógica de viajes, ofertas, pricing, pagos, wallet, suscripciones, Delivery;
- auth/bootstrap (`lib/mobile_main.dart`, `lib/core/`), llamadas privadas, OTP;
- migraciones SQL, RLS, RPC, Edge Functions o aislamiento `preview`/`production`;
- workflows de CI, release gate, versionado o artefactos Android;
- más de un módulo a la vez o refactors amplios.

Mecanismos: `/codex:review` (revisión del diff) o `/codex:adversarial-review` (revisión crítica). Los hallazgos se verifican antes de aplicarlos; un hallazgo no verificado no se presenta como hecho.

## 4. Control de concurrencia (sin ediciones simultáneas)

- Antes de editar, Claude ejecuta `git status` y no sobrescribe trabajo existente no confirmado.
- Mientras una tarea Codex con escritura (`--write`) esté en curso, **Claude no edita archivos** en el mismo checkout.
- Cada delegación a Codex nombra los archivos/directorios que puede tocar; Claude no edita esos archivos hasta revisar el resultado.
- Si se necesita trabajo paralelo real, usar un `git worktree` separado para Codex.
- Tras cada tarea de Codex, Claude revisa `git status` + `git diff` y descarta/corrige lo que salga del alcance acordado.
- Revisiones, diagnósticos e investigaciones de Codex se ejecutan **sin `--write`** (solo lectura).

## 5. Límites

Refuerzan (no reemplazan) `AGENTS.md` §4, §11, §12 y §14.

### 5.1 Prohibiciones permanentes (no autorizables por este protocolo)

Siguen siendo prohibiciones de `AGENTS.md`; solo pueden cambiar mediante una decisión del propietario documentada en `AGENTS.md`/handoff maestro, nunca por una aprobación puntual en una conversación:

- editar o commitear directamente en `main`;
- ejecutar migraciones/Edge Functions de Express en un proyecto distinto de `zgpijrznvaskgcmauwxx`;
- mezclar datos/cuentas QA con Producción o quitar guards de aislamiento;
- guardar secretos en Git;
- todo lo listado en `AGENTS.md` §14.

### 5.2 Operaciones que requieren autorización explícita y puntual del propietario

- commit, push, merge, tag, release, PR, ejecución manual de workflows y deployment;
- desplegar a Producción o promover artefactos Producción;
- migraciones o Edge Functions en Producción;
- cambios de secretos, credenciales, pagos, webhooks, RLS, autenticación, DNS o infraestructura de Producción;
- borrado de datos de Producción;
- cualquier otra operación destructiva o irreversible: **detenerse y preguntar**.

Una autorización vale solo para la operación concreta aprobada; no se extiende a otras ni a otras sesiones.

## 6. Respaldo, pruebas y documentación

- Crear rama/tag de respaldo antes de cambios de riesgo (convención existente: `backup/<descripcion>-<AAAAMMDD>`).
- Ejecutar las validaciones exigidas por `AGENTS.md` y `docs/QA_AUTOMATION.md` (p. ej. `flutter analyze` de ambos entrypoints y `flutter test` para cambios Flutter).
- Si una prueba falla: reportarla con su salida real; no ocultarla, no desactivarla y no declarar la tarea terminada.
- **CODE CHANGED = DOCS MUST CHANGE** aplica igual a cambios hechos por Codex.

## 7. Configuración técnica

- `CLAUDE.md` (raíz): importa `AGENTS.md` para Claude Code y apunta a este documento.
- `AGENTS.md` §15: puntero a este documento para Codex y cualquier otro agente.
- `.claude/settings.json` (compartido): habilita el plugin Codex y exige confirmación manual (`ask`) para commit, push, merge, rebase, `reset --hard`, tag, `gh pr create/merge`, `gh release`, `gh workflow run`, `gh api`, CLIs `supabase`/`shorebird`/`firebase`/`psql` y las herramientas MCP de Supabase con escritura.
- **Limitaciones de `ask` (no es una barrera completa):** las reglas son por patrón de comando y pueden no cubrir variantes (otras formas de invocar git, HTTP directo con `curl`, scripts, otro prefijo MCP); el modo `bypassPermissions` omite los prompts. La barrera real es la regla humana de §5: aunque un prompt se confirme o no aparezca, la operación necesita autorización explícita.
- **Codex no está gobernado por `.claude/settings.json`.** Sus comandos se ejecutan en su propio sandbox (solo lectura por defecto; escritura solo con `--write`). Por eso cada delegación de Claude a Codex debe incluir en el prompt: alcance exacto (archivos permitidos), prohibiciones de §5 (sin commit/push/merge/deploy/Supabase/Producción) y, si existe, la autorización concreta del propietario. Codex además lee `AGENTS.md` directamente.
- `.claude/settings.local.json` es personal y está ignorado por el `.gitignore` del repositorio.
- El gate de revisión al detenerse (`/codex:setup --enable-review-gate`) queda **desactivado**; activarlo solo si el propietario lo pide.
- Requisitos locales: CLI Codex instalada y sesión iniciada (`/codex:setup`; si falta login, `!codex login`).
