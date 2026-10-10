# Memoria del proyecto Express · 2026-10-10

Resumen para cualquier IA o persona que retome el proyecto. Cada punto indica si está **verificado** o **no verificado**. No reemplaza al handoff maestro (`AI_HANDOFF_2026-10-06_MASTER.md`) ni a `OWNER_RULES_2026-10-10.md`, que son las fuentes de reglas.

## 1. Reglas del propietario (prioridad máxima)
- Una app, una rama, dos canales. Todo cambio se lanza **primero solo a Preview** para que el propietario lo pruebe.
- **Preguntar antes** de publicar APK/AAB, fusionar en `main` (que publica la web real), tocar Producción o subir a Play Store.
- **Respaldo antes de cambiar** (rama `backup/<tema>-<fecha>` o tag).
- **Revisar cambios previos** del mismo módulo antes de tocar algo.
- Todo cambio se documenta en `docs/CHANGELOG_ACTIVE.md`.
- Estado de estas reglas: existen en la rama `claude/express-admin-audit-cp07ml`, **no en `main`** (verificado).

## 2. Roles (según la rama de auditoría; verificado)
- **Propietario:** prioriza y autoriza Producción, datos reales, Play, APK/AAB y merges a `main`.
- **Claude:** arquitecto, controlador y revisor. Desde 2026-10-10 el propietario indicó que también programa. Esta decisión verbal no está escrita en `CLAUDE.md`, que aún dice lo contrario.
- **ChatGPT/Codex:** programador de specs `[SPEC]` en ramas `chatgpt/*` o `codex/*`. No fusiona su propio PR.

## 3. Canales y arquitectura de la app (verificado en código)
- Entrypoints: `lib/mobile_main.dart` (Android, único), `lib/web_preview.dart` (web), `lib/preview_main.dart` (solo envoltorio).
- Preview/Producción en Android: `EXPRESS_PREVIEW_MODE` en `lib/mobile_main.dart:83`. En web lo resuelve el servidor (`resolve_current_runtime_environment`).
- Las RPC reciben `p_channel`. Supabase oficial: `zgpijrznvaskgcmauwxx`. QA de pruebas: `xbphilqezmwfjfpdbwad`.
- 62 archivos Dart, unas 56.400 líneas. Los más grandes: `video_style_home.dart` (15.805), `express_delivery_v2_page.dart` (6.861), `connected_experience.dart` (5.777).
- 160 migraciones SQL (la última del 2026-10-09). 11 Edge Functions en el repo.
- Admin (`jorge2610g/Adminexpress`): panel separado. Preview en `/preview/`. Arquitectura **no verificada** (informe pendiente).

## 4. Flujo de trabajo vigente
1. Spec `[SPEC]` en `docs/specs/`.
2. Respaldo previo.
3. Rama propia y PR a `main`. Se disparan `release-change-inventory`, `express-single-app-qa` (análisis, tests, build Web) y otros según rutas. Sin APK salvo etiqueta `native-qa`.
4. Revisión contra la spec.
5. Fusión a `main` **solo con orden del propietario**. `deploy-web.yml` publica la web real.
6. Migraciones y Edge Functions se aplican a mano en Supabase. No hay workflow que las despliegue (verificado).
7. Producción y Play: mismo APK/AAB aprobado, sin recompilar, por orden explícita.

## 5. Estado de Supabase y funciones (verificado con list_projects; funciones según inventario de la rama)
- Dos proyectos, ambos activos. No hay proyectos pausados ni ajenos a Express.
- Edge Functions de producción: 18 con estado `ACTIVE`, pero 7 están retiradas según el inventario (`didit-*` ×4, `phone-otp`, `unimatrix-health-check`, `zego-health-check`). **No reactivar sin orden.**
- Pendientes de despliegue: `express-push-dispatch` (commit 894348c) y la corrección de permisos de `express-load-lab`.
- Contradicción: `CHANGELOG_ACTIVE.md` dice que Didit quedó habilitado en Bolivia el 2026-10-05; el inventario dice que está retirada. **Por confirmar.**

## 6. Seguridad (verificado en parte)
- **H1 (alto, verificado):** `auth_login_guard_record_failure` es ejecutable por `anon`. Tres intentos con un email bloquean esa cuenta. Ver `docs/reviews/SECURITY-2026-10-10-secdef-exposure.md`. **Sin corregir; requiere autorización.**
- H2–H5: ver el mismo documento.
- Riesgos de workflows y funciones (informe de arquitectura, no verificado en vivo):
  - `build-android.yml` con cron cada 5 min que atiende una cola y compila artefactos firmados de Producción.
  - `deploy-web.yml` acepta `/deploy-pages` de cualquier autor en el issue 1 (no se verificó la visibilidad del repo).
  - `marketplace-payments` con variable mal escrita (`payment_id`) que da error 500.
  - `express-push-dispatch` con comparación de secreto sin tiempo constante.
  - Tres funciones admin autorizan solo con `is_admin`.

## 7. Historial (verificado parcialmente)
- 2026-09-20 primer commit. 2026-10-04 `AGENTS.md`. 2026-10-06 handoff maestro y entrypoint único. 2026-10-08 Web First y app única. 2026-10-09 contrato Preview→Producción (propuesta). 2026-10-10 auditoría de seguridad y roles.
- Migraciones de auditoría E1, E1b, E4 y E6: el changelog dice aplicadas en Producción (~01:21 UTC del 2026-10-10). La regla que prohíbe a Claude aplicarlas es posterior (04:13 UTC). **Por confirmar en la base.**

## 8. Contradicciones abiertas
- Contador de build de Play: el handoff dice 131 con siguiente 132; el changelog del 2026-10-08 dice 137 con siguiente 138. **Verificar en Play Console.**
- Gate de Producción: `AGENTS.md` dice que no exige Preview; los documentos del 2026-10-08 dicen que el worker sí lo exige. **Verificar `android-build-worker`.**
- "Preview" tiene cuatro sentidos: APK, canal de datos, panel `/preview/` y QA.
- PR #148 ya cerrada aunque el handoff pide fusionarla.
- Varios documentos citados faltan en `main` (`CLAUDE.md`, `CHATGPT.md`, `AI_ROLES_WORKFLOW.md`, `docs/PHONE_OTP_ROUTER.md`).

## 9. Pendientes de decisión del propietario
1. Autorizar la corrección de H1 de seguridad (plan en el documento de seguridad).
2. Decidir qué hacer con el cron de `build-android.yml`.
3. Confirmar el estado de Didit en Bolivia.
4. Canal de Preview para probar la PR #156 del pasajero.
5. Llevar las reglas de roles a `main` (PR de documentación).
6. Confirmar si la PR #57 de Adminexpress, fusionada el 2026-10-10 a las 14:49 UTC, llegó a Producción.

## 10. No verificado
- Historial anterior a 2026-10-06 (clon superficial).
- Versiones 1.5.x con fechas.
- Estado real de RLS y RPC en la base, de la cola `build_jobs`, de tags y de ejecuciones de Actions.
- Arquitectura completa de Adminexpress.
