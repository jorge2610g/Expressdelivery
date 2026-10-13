
> **DECISIÓN DEFINITIVA DEL PROPIETARIO — 2026-10-12: UNA WEB, UNA APK, DOS CONTEXTOS INTERNOS.** Fuente de verdad por encima de toda documentación antigua. Adminexpress usa solo `https://admin.expressviajes.online/`; Express usa solo el paquete Android oficial `com.express.usuario1`. NO crear, compilar, publicar ni operar `Express Preview` como APK distinta, `com.express.usuario.preview`, `com.express.usuario.qa`, web Preview independiente, espejo o otro despliegue. Preview y Producción se separan **solo por identidad y aislamiento de datos autorizado en backend**, dentro de la misma aplicación; «probar Preview» nunca implica otra aplicación. El candidato oficial firmado se prueba físicamente y se aprueba sin alterar su firma ni reempaquetarlo. Mantener sin excepción el aislamiento de zonas, viajes, conductores, pedidos, dinero, RLS y permisos. Ramas/PR temporales y QA automatizado son admisibles, pero jamás una segunda aplicación. Solo una revocación explícita del propietario puede cambiar esta norma. Los documentos históricos que describen dos paquetes, una segunda APK o Web Preview independiente quedan superados.

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

1. `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md` — **decisión más reciente sobre builds/QA**
2. `docs/AI_HANDOFF_2026-10-06_MASTER.md` — **fuente autoritativa vigente**
2. `docs/ONE_APP_ONE_PANEL_2026-10-12.md` — **regla absoluta del propietario: una web y una APK**
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

## 5. Una sola aplicación Android oficial

- **Paquete único:** `com.express.usuario1` (Express), mismo APK/AAB firmado tanto para pruebas internas como para Producción.
- **Entry point único:** `lib/mobile_main.dart`.
- El entorno de datos se determina después de autenticar por `resolve_current_runtime_environment` y reglas de backend, jamás por package distinto ni modo de compilación.
- `lib/preview_main.dart` queda solo como alias histórico de `express.main()`; no tiene startup propio, ni selección de entorno, ni está autorizado como target CI.
- `lib/web_preview.dart` es el nombre heredado del entrypoint de la **web Express vigente**, no otra web Preview. No cambiarlo sin migración segura de su workflow actual.
- No crear `com.express.usuario.preview`, `com.express.usuario.qa` ni otro package. No generar más APK Preview ni QA independiente.

## 6. Candidato único y validación antes de publicar

- GitHub Actions compila **el paquete real y único `com.express.usuario1`** desde el código compartido.
- Candidato: APK y AAB reales con la misma firma, SHA y build controlado; el APK se prueba físicamente con cuenta y zona de Prueba.
- La aprobación y promoción utilizan los artefactos verificados sin recompilar; **nunca publicar Google Play sin autorización y pruebas reales**.
- El entorno de prueba mantiene aislamiento de cuentas, conductores, zonas, viajes, tarifas, pedidos, billeteras y liquidaciones en el backend.
- QA web/Flutter es automático, pero no debe generar otro APK ni otro sitio para 'Preview'.
- Contrato vigente: `docs/ONE_APP_ONE_PANEL_2026-10-12.md`.

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
