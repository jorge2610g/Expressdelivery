# Roles de IA y flujo de trabajo (desde 2026-10-10)

Decisión del propietario: **Claude = arquitecto, controlador y revisor. La programación la hace Codex, ChatGPT u otra IA programadora.** Claude no programa en ningún caso (regla permanente en `CLAUDE.md`).

## Responsabilidades

| Rol | Hace | No hace |
|---|---|---|
| **Claude (arquitecto/revisor)** | Analiza problemas y causa raíz; diseña la solución; escribe la **especificación de tarea** (alcance, archivos, criterios de aceptación, pruebas, riesgos, rollback); revisa cada PR de Codex contra la especificación, la arquitectura y la seguridad; verifica en Supabase (logs, permisos, datos) y en QA; aprueba o pide cambios; mantiene la documentación de arquitectura. | No escribe código, SQL ni Edge Functions; no aplica migraciones ni despliega; no fusiona. Si hay fallos los devuelve con evidencia a la IA programadora. |
| **IA programadora (Codex / ChatGPT / otra)** | Implementa exactamente la especificación en una rama propia; agrega pruebas; actualiza `docs/CHANGELOG_ACTIVE.md`; abre PR con la plantilla de abajo. | No cambia el alcance por su cuenta; no aplica migraciones ni despliega Edge Functions en Producción; no fusiona su propio PR. |
| **Propietario** | Prioriza; autoriza Producción, datos reales, permisos y releases; prueba en dispositivo. | — |

## Flujo

1. **Spec** — Claude crea un issue `[SPEC] …` (o archivo en `docs/specs/`) con la plantilla.
2. **Implementación** — Codex trabaja en `codex/<tema>`, abre PR que referencia la spec.
3. **Revisión** — Claude revisa: cumple la spec, CI verde (`flutter analyze lib`, tests), sin cambios fuera de alcance, seguridad Preview/Producción, docs actualizadas. Resultado: aprobado / cambios pedidos.
4. **Backend** — migraciones y Edge Functions las aplica la IA programadora: primero QA (`xbphilqezmwfjfpdbwad`), luego Producción **solo con autorización** del propietario; con respaldo y rollback. Claude verifica (solo lectura) antes y después.
5. **Merge y release** — el propietario fusiona/autoriza; APK/AAB por el gate vigente.

## Plantilla de especificación

```
# [SPEC] <título>
Contexto / problema (con evidencia):
Objetivo:
Fuera de alcance:
Archivos a tocar:
Diseño (pasos concretos):
Criterios de aceptación (verificables):
Pruebas requeridas:
Riesgos y compatibilidad (APK instalados, Preview/Producción):
Rollback:
Documentación a actualizar:
```

## Checklist de revisión (Claude)

- [ ] Cumple la spec y nada más.
- [ ] `flutter analyze lib` sin errores; tests nuevos y existentes pasan.
- [ ] No rompe aislamiento Preview/Producción (RPC con `p_channel`, sin escrituras reales desde Preview).
- [ ] Sin secretos, URLs internas o excepciones crudas visibles al usuario.
- [ ] Compatible con APK instalados (firmas de RPC sin cambios incompatibles).
- [ ] Migraciones: respaldo + rollback + probadas en QA.
- [ ] `docs/CHANGELOG_ACTIVE.md` y docs del módulo actualizados.

Reglas generales: `AGENTS.md`, `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md`.

## Specs emitidas
- `docs/specs/SPEC-2026-10-10-driver-refresh-load.md` — reducir recargas del panel del conductor (pendiente de implementación por la IA programadora).

## Formato de devolución y revisiones
- La IA programadora entrega con `docs/AI_RESPONSE_FORMAT.md`.
- Claude revisa y guarda `docs/reviews/REVIEW-<PR>-<tema>.md` (veredicto, evidencia propia, hallazgos, pruebas exigidas y prompt para pegar).
- Revisiones emitidas: `docs/reviews/REVIEW-PR150-driver-refresh-2026-10-10.md` (CAMBIOS REQUERIDOS: B1 throttle descarta eventos, B2 refresco ligero sobrescribe estado más nuevo).
