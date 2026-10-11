# Reglas permanentes del propietario · 2026-10-10

Aplican a Claude y a cualquier IA que trabaje en Express. Son de mayor prioridad que el resto de la documentación de rol.

## 1. Una sola app, una sola rama, dos canales
- La app es una sola. Preview y Producción son canales de la misma rama, no ramas distintas.
- **Todo cambio se lanza primero solo a Preview**, para que el propietario lo pruebe.
- **Nunca** se lanza a Producción, ni se publica APK/AAB, ni se sube a Google Play, sin una orden explícita y posterior del propietario.

## 2. Preguntar antes de publicar
Antes de cualquiera de estas acciones, preguntar al propietario y esperar respuesta:
- publicar un APK o AAB (incluido el de QA si va a salir del repo);
- fusionar en `main` o cualquier rama que despliegue la web real (`deploy-web.yml`);
- aplicar migraciones, funciones o cambios de datos en Producción;
- subir a Google Play.

## 3. Respaldo antes de cambiar
- Antes de cambiar código, crear un respaldo (rama `backup/<tema>-<fecha>` o tag) del estado actual, y anotar el SHA en la PR o el changelog.
- Si algo se daña, volver al respaldo es preferible a parchear sobre el daño.

## 4. Revisar lo anterior
- Antes de cada cambio nuevo, revisar los cambios previos del mismo módulo (PRs abiertas, changelog, revisiones en `docs/reviews/`) para no pisar ni romper trabajo anterior.

## 5. Documentar
- Todo cambio se documenta en `docs/CHANGELOG_ACTIVE.md` (regla de `AGENTS.md`).
