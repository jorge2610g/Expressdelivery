# Política oficial de documentación — Expressdelivery

> **Estado:** obligatoria  
> **Aplica a:** humanos, IA, agentes de código, CI/CD y cambios manuales  
> **Regla base:** ningún cambio está terminado si no está documentado.

## 1. Regla universal

**CODE CHANGED = DOCS MUST CHANGE**

Toda modificación al proyecto exige documentación asociada, sin excepciones por tamaño.

Incluye:

- código Dart/Flutter;
- UI/UX;
- assets;
- dependencias;
- Android/iOS;
- Supabase;
- SQL/migraciones;
- Edge Functions;
- workflows;
- QA;
- scripts;
- versiones/builds;
- configuración;
- feature flags;
- permisos;
- releases;
- fixes;
- eliminaciones;
- rollbacks;
- cambios de comportamiento;
- cambios de reglas de negocio.

## 2. Cuándo documentar

La documentación debe quedar:

1. idealmente en el mismo commit del cambio; o
2. en un commit documental inmediatamente asociado.

Pero siempre **antes** de:

- declarar la tarea terminada;
- compartir un build como válido;
- promover a Preview;
- aprobar Preview;
- promover a Producción;
- entregar el trabajo a otra IA/desarrollador.

## 3. Archivos obligatorios

Como mínimo:

- `docs/CHANGELOG_ACTIVE.md`: cada cambio;
- `docs/AI_HANDOFF_2026-10-06_MASTER.md`: cambios que afecten estado, release, QA, versión, arquitectura o reglas;
- `docs/START_HERE_EXPRESS.md`: cuando cambie el estado general o punto de continuación;
- documentación específica del módulo cuando exista.

`AGENTS.md` debe señalar siempre cuál es el handoff maestro autoritativo vigente.

## 4. Contenido mínimo de una entrada

Registrar:

- fecha;
- objetivo;
- qué se modificó;
- qué se eliminó;
- archivos/módulos afectados;
- versión/build;
- SHA cuando exista;
- entorno: Preview/Producción/backend/web;
- si requiere nueva base, patch o no requiere APK;
- estado de QA;
- riesgos o pendientes;
- instrucciones para continuar;
- prohibiciones relevantes.

## 5. Eliminaciones

Toda eliminación debe indicar:

- qué se borró;
- por qué;
- qué lo reemplaza;
- desde qué versión/build;
- si queda legado/compatibilidad.

Una IA futura no debe poder confundir una eliminación intencional con “código faltante”.

## 6. Releases

Todo release o intento de release debe documentar:

- versión;
- build;
- SHA;
- workflow/run;
- artefactos realmente creados;
- tag/release;
- gate;
- QA;
- resultado final.

Un workflow verde sin artefacto real NO se documenta como release exitoso.

## 7. Bloqueo de cierre

Antes de cerrar una tarea, comprobar:

- [ ] implementación terminada;
- [ ] documentación actualizada;
- [ ] changelog actualizado;
- [ ] versión/build/SHA registrados si aplica;
- [ ] estado de QA registrado;
- [ ] pendientes registrados;
- [ ] instrucciones de continuidad actualizadas.

Si falta documentación aplicable, la tarea permanece **abierta**.

## 8. Obligación de cualquier IA

Antes de editar, toda IA debe leer:

1. `AGENTS.md`
2. `docs/AI_HANDOFF_2026-10-06_MASTER.md`
3. este archivo
4. `docs/CHANGELOG_ACTIVE.md`
5. documentación específica del módulo

La IA debe comprobar que la documentación coincide con el repositorio y con los workflows reales. Si encuentra desfase, debe corregirlo como parte de la tarea y documentar la corrección.

## 9. No usar memoria como única fuente

Memorias de chat o contexto previo pueden ayudar, pero el repositorio es la referencia persistente para continuidad.

Una decisión operativa importante que solo exista en conversación y no en el repo se considera **no documentada** hasta incorporarla.
