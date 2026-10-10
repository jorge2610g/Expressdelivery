> **HANDOFF 2026-10-10 (leer primero):** `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md`.
> Una app, una base `zgpijrznvaskgcmauwxx`, dos entornos (`preview`/`production`)
> por canal. `xbphilqezmwfjfpdbwad` = solo banco de pruebas. RPC admin sin
> `p_channel` ahora exigen permiso de Producción (E1/E1b); conductores se aprueban
> solos al verificar documentos (E4); `anon` con mínimo privilegio (E6). El código
> desplegado de Edge Functions puede diferir de git: comparar byte a byte antes de
> desplegar. Pendientes y rollbacks en el handoff.
>
> **QA video 2026-10-08:** un usuario en Iquique vio `Sugerido $5`
> durante la primera cotización y luego `$1500.0`; no usar
> el monto local predeterminado `fare=5` como mínimo real. Siempre
> esperar el RPC de tarifa por coordenadas/categoría para mostrar
> precio y activar Confirmar; descartar respuestas viejas al
> cambiar Express/Moto; mostrar reintento si falla. Los datos QA
> y Producción permanecen aislados. Ver
> `docs/CHANGELOG_ACTIVE.md`.
>
# AGENTS.md — Expressdelivery

Este archivo es la puerta de entrada obligatoria para cualquier IA, agente o desarrollador que trabaje en Express.

> **CAMBIO AUTORIZADO 2026-10-08 — WEB FIRST / UNA SOLA APP:** leer primero `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`. Esta decisión sustituye la compilación Preview Android automática por QA Web continua y APK nativo temporal a petición. El release gate Android histórico sigue activo y es manual hasta migrarlo con QA; NO publicar ni deshabilitar el gate sin reemplazo probado. La separación de datos Preview/Producción permanece obligatoria.

> **GATE NUEVO 2026-10-08:** el candidato firmado del APK/AAB de Producción se compila desde `main` (mismo `lib/mobile_main.dart`), se prueba el APK real, se certifican los hashes por administrador, se aprueba y se promueve **sin recompilar**. No requiere Preview Android. Los requisitos antiguos Preview/Shorebird de este archivo son históricos y no aplican al gate unificado. Mantenerlos solo como rollback manual hasta pruebas reales del primer candidato. El runtime de datos Preview sigue aislado.

## 1. Lectura obligatoria antes de editar

Leer en este orden:

0. `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md` — **estado más reciente: seguridad, permisos, Edge Functions, pendientes**
1. `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md` — **decisión más reciente sobre builds/QA**
2. `docs/AI_HANDOFF_2026-10-06_MASTER.md` — **fuente autoritativa vigente**
2. `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md` — **regla estricta Preview → Producción desde +163**
3. `docs/DOCUMENTATION_POLICY.md`
4. `docs/CHANGELOG_ACTIVE.md`
5. `docs/START_HERE_EXPRESS.md` — contexto general/histórico; no prevalece sobre el handoff maestro
6. `docs/QA_AUTOMATION.md`
7. `docs/PRIVATE_VOICE_CALLS.md`
8. `docs/FLOATING_DRIVER_OFFERS.md` — requisito +155 de ofertas sobre otras apps
9. `docs/PHONE_OTP_ROUTER.md`
10. `docs/GOOGLE_PLAY_SUBMISSION.md`
11. documentación específica del módulo a modificar

Los handoffs del 2026-10-05 y anteriores son historial. Si contradicen el handoff maestro del 2026-10-06, prevalece el más nuevo.

## 2. Regla de documentación

**CODE CHANGED = DOCS MUST CHANGE**

Ningún cambio está terminado hasta documentarlo. Como mínimo actualizar:

- `docs/CHANGELOG_ACTIVE.md`;
- el handoff maestro si cambia estado, arquitectura, reglas, release o QA;
- el documento específico del módulo.

Una decisión importante que solo exista en una conversación se considera no transferida.

## 3. Alcance del repositorio

`Expressdelivery` contiene la app Flutter de Express para Pasajero + Conductor y backend/migraciones compartidas.

El panel administrativo vive separado:

- repo: `jorge2610g/Adminexpress`
- web conocida: `admin.expressviajes.online`

No volver a incrustar Adminexpress dentro de esta app.

## 4. Backend correcto

Supabase Project Ref oficial:

`zgpijrznvaskgcmauwxx`

Nunca ejecutar migraciones o Edge Functions de Express contra otro proyecto.

## 5. Entry point único Android y package IDs

**REGLA AUTORITATIVA DESDE +163:** Preview y Producción compilan el mismo entrypoint funcional:

- Android Preview: `lib/mobile_main.dart`
- Android Producción: `lib/mobile_main.dart`
- Web: `lib/web_preview.dart`

`lib/preview_main.dart` queda únicamente como wrapper de compatibilidad/local. **No puede contener startup propio y ningún workflow oficial debe usarlo como target.**

Configuración:

- Preview: `EXPRESS_PREVIEW_MODE=true`
- Producción: `EXPRESS_PREVIEW_MODE=false`

Package IDs:

- Producción: `com.express.usuario1`
- Preview: `com.express.usuario.preview`

El package/Firebase/canal pueden diferir; la lógica funcional no.

Documento obligatorio: `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`.

No cambiar esta arquitectura ni los package IDs sin decisión explícita y documentada.

## 6. Regla Android de artefactos

### Preview

- **APK solamente**
- **NO AAB**
- si usa Shorebird, entregar la base:
  `preview-shorebird-v<VERSION>-build<BUILD>/app-release.apk`

### Producción

- APK + AAB
- debe salir del mismo SHA aprobado como Preview;
- debe compilar el mismo `lib/mobile_main.dart` que Preview;
- no puede introducir una implementación funcional separada;
- **build number/versionCode independiente del contador Preview**;
- APK y AAB de la misma release Producción comparten el mismo build number;
- el candidato Producción se precompila antes de aprobar Preview;
- el contador Google Play es independiente: siguiente build = `production_store_build_number + 1`;
- Preview/builds internos nunca pueden avanzar el contador de Producción;
- antes y después de compilar, el builder debe validar versión + build + SHA + código móvil vigente + manifiesto/hashes del artefacto.

## 7. Trazabilidad obligatoria

Una release solo es válida si coinciden:

- versión funcional;
- build Preview y build Producción identificados por separado;
- SHA;
- artefacto;
- tag/release;
- `app_release_gate`;
- workflow;
- SHA realmente probado por QA.

Flujo obligatorio:

`commit -> Preview Shorebird + candidato Producción precompilado -> gate -> QA exacto -> aprobación -> promoción sin recompilar`

No confiar en un workflow verde si no generó el artefacto correcto.

## 8. Shorebird

Patch solo cuando Shorebird confirma compatibilidad.

Si hay cambios nativos/DEX no explicados:

- no forzar `--allow-native-diffs`;
- crear nueva base Preview APK.

Estado actual y causa de +152: leer el handoff maestro.

## 9. Llamadas privadas

Viaje activo Pasajero ↔ Conductor usa ZEGOCLOUD mediante `ExpressPrivateVoiceCall`.

No debe abrir:

- `tel:`;
- aplicación Teléfono;
- Zoom;
- selector externo.

Los números reales no se comparten entre las partes.

## 10. QA

Workflow principal:

`Express QA Auditor`

QA debe auditar exactamente el SHA registrado en el gate. Si el SHA del trigger y el gate no coinciden, debe bloquear.

Un rojo puede ser:

- fallo real de producto;
- infraestructura QA;
- prueba no concluyente;
- identidad/versionado incorrecto.

No modificar producto sin evidencia de fallo de producto.

## 11. Separación de entornos

Runtime:

- `preview`
- `production`

No mezclar datos/cuentas QA con Producción. No eliminar guards de aislamiento para “hacer pasar” una prueba.

## 12. Seguridad

No guardar en Git:

- service-role keys;
- JWT privados;
- contraseñas;
- tokens GitHub;
- keystores;
- passwords de firma;
- ServerSecrets RTC;
- secretos OTP/SMS/WhatsApp;
- credenciales privadas de proveedores.

## 13. Antes de editar

1. leer el handoff maestro;
2. revisar `pubspec.yaml`;
3. revisar SHA de `main`;
4. revisar workflows recientes;
5. revisar release/gate si toca Android;
6. decidir si es Dart-only, backend o cambio nativo;
7. definir QA;
8. implementar;
9. documentar;
10. no declarar “listo” sin evidencia.

## 14. No hacer

- no cambiar package IDs;
- no regenerar firma sin necesidad;
- no saltarse el release gate;
- no generar AAB Preview;
- no promover Producción desde otro SHA;
- no copiar el build number Preview al package Producción;
- no recompilar Producción después de aprobar Preview si ya existe candidato firmado del mismo SHA;
- no forzar native diffs Shorebird;
- no volver a llamadas externas en viaje activo;
- no mezclar datos Preview/Producción;
- no crear lógica de startup propia en `lib/preview_main.dart`;
- no usar `--target lib/preview_main.dart` en workflows oficiales;
- no duplicar funciones para tener una variante Preview y otra Producción;
- no asumir que una feature pedida ya está implementada;
- no restaurar código histórico eliminado sin revisar el handoff vigente.
