# AGENTS.md — Expressdelivery

Este archivo es la puerta de entrada obligatoria para cualquier IA, agente o desarrollador que trabaje en Express.

## 1. Lectura obligatoria antes de editar

Leer en este orden:

1. `docs/AI_HANDOFF_2026-10-06_MASTER.md` — **fuente autoritativa vigente**
2. `docs/DOCUMENTATION_POLICY.md`
3. `docs/CHANGELOG_ACTIVE.md`
4. `docs/START_HERE_EXPRESS.md` — contexto general/histórico; no prevalece sobre el handoff maestro
5. `docs/QA_AUTOMATION.md`
6. `docs/PRIVATE_VOICE_CALLS.md`
7. `docs/FLOATING_DRIVER_OFFERS.md` — requisito +155 de ofertas sobre otras apps
8. `docs/PHONE_OTP_ROUTER.md`
9. `docs/GOOGLE_PLAY_SUBMISSION.md`
10. documentación específica del módulo a modificar

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

## 5. Entradas y package IDs

Entradas:

- Producción Android: `lib/mobile_main.dart`
- Preview Android: `lib/preview_main.dart`
- Web: `lib/web_preview.dart`

Package IDs:

- Producción: `com.express.usuario1`
- Preview: `com.express.usuario.preview`

No cambiarlos sin decisión explícita y documentada.

## 6. Regla Android de artefactos

### Preview

- **APK solamente**
- **NO AAB**
- si usa Shorebird, entregar la base:
  `preview-shorebird-v<VERSION>-build<BUILD>/app-release.apk`

### Producción

- APK + AAB
- debe salir del mismo SHA aprobado como Preview

## 7. Trazabilidad obligatoria

Una release solo es válida si coinciden:

- versión;
- build;
- SHA;
- artefacto;
- tag/release;
- `app_release_gate`;
- workflow;
- SHA realmente probado por QA.

Flujo obligatorio:

`commit -> Shorebird -> artefacto -> release/tag -> gate -> QA exacto -> aprobación -> Producción mismo SHA`

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
- no forzar native diffs Shorebird;
- no volver a llamadas externas en viaje activo;
- no mezclar Preview/Producción;
- no asumir que una feature pedida ya está implementada;
- no restaurar código histórico eliminado sin revisar el handoff vigente.
