# CLAUDE.md — Permiso de programación (decisión del propietario, 2026-10-10)

> **Vigente desde 2026-10-14:** la arquitectura de entornos está en `docs/ARQUITECTURA_UNICA_2026-10-14.md`. Prevalece sobre cualquier regla anterior de entornos (dos páginas, APK Preview, `ADMIN_ENV`).

**Claude y todos los agentes de Claude Cloud pueden programar en este proyecto:**
código de la app, SQL, migraciones, Edge Functions, workflows y scripts.

Las reglas de rol anteriores ("Claude no programa") quedan **eliminadas por ahora**.
El propietario indicó que las volverá a solicitar cuando las necesite.

## Reglas que siguen vigentes
Las reglas de seguridad del propietario están en `docs/OWNER_RULES_2026-10-10.md`:
- Todo cambio se lanza primero a Preview para que el propietario lo pruebe.
- Antes de publicar un APK o AAB, fusionar en `main` (que despliega la web real) o subir a Play Store, se pregunta al propietario y se espera su respuesta.
- Antes de cambiar código, se crea un respaldo (rama `backup/<tema>-<fecha>`).
- Antes de cada cambio se revisan los cambios previos del mismo módulo.
- Todo cambio se documenta en `docs/CHANGELOG_ACTIVE.md`.
- Sin acciones en Producción (migraciones, datos, permisos) sin orden explícita del propietario.
