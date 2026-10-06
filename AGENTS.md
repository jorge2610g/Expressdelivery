# AGENTS.md — Expressdelivery

Este archivo existe para que cualquier IA, agente de código o desarrollador pueda entrar al repositorio sin romper Preview, Producción, firma Android, Supabase ni el flujo de QA.

## Regla 0: leer antes de editar

Orden obligatorio de lectura:

1. `docs/AI_HANDOFF_2026-10-05_RELEASE_TRACEABILITY.md`
2. `docs/DOCUMENTATION_POLICY.md`
3. `docs/CHANGELOG_ACTIVE.md`
4. `docs/START_HERE_EXPRESS.md`
5. `docs/QA_AUTOMATION.md`
6. `docs/SAFE_IMPLEMENTATION_ROADMAP.md`
7. `docs/AI_HANDOFF_2026-10-04.md` solo como historial/contexto anterior

El documento `AI_HANDOFF_2026-10-05_RELEASE_TRACEABILITY.md` es la fuente autoritativa vigente para Preview, Shorebird, QA, release gate, trazabilidad y reglas de continuidad. Si contradice documentación anterior, prevalece el handoff más nuevo.

## Regla 0.1: ningún cambio termina sin documentación

Regla oficial permanente:

`CODE CHANGED = DOCS MUST CHANGE`

Todo cambio, incluso pequeño, debe actualizar `docs/CHANGELOG_ACTIVE.md` y la documentación de continuidad aplicable antes de considerarse terminado, compartir un build, aprobar Preview o promover a Producción.

Si una IA encuentra documentación desfasada respecto al código, workflows o gate real, debe corregir ese desfase como parte de la tarea antes de continuar.

## Regla 0.2: trazabilidad Android obligatoria

Nunca confiar únicamente en el nombre del workflow o en un resultado verde. Para certificar una Preview deben coincidir simultáneamente:

- versión;
- build;
- SHA fuente;
- APK realmente generado;
- tag/release;
- `app_release_gate`;
- identidad que QA realmente probó.

Un workflow verde que no creó artefacto no cuenta como build válido. Un QA ejecutado contra una versión anterior no certifica la nueva versión.


## Alcance del repositorio

`Expressdelivery` contiene la app Flutter de Express para pasajero + conductor y el backend/migraciones compartidas con Adminexpress.

El panel administrativo NO debe volver a integrarse aquí. Vive en:

- repo: `jorge2610g/Adminexpress`
- web de uso actual: `admin.expressviajes.online`

## Backend correcto

Supabase Project Ref:

`zgpijrznvaskgcmauwxx`

Nunca ejecutar migraciones de Express contra otro proyecto.

## Entradas activas

- Producción Android: `lib/mobile_main.dart`
- Preview Android: `lib/preview_main.dart`
- Web: `lib/web_preview.dart`

Package IDs:

- Producción: `com.express.usuario1`
- Preview: `com.express.usuario.preview`

## Baseline de Producción

Release Android publicada/generada:

- versión: `1.5.87+131`
- SHA exacto aprobado: `45c2aff26cd27229e445461d2f129023bf6f60df`
- tag: `android-v1.5.87-build131`
- firma: `production`

El `main` puede ir por delante de este SHA con cambios QA/backend. No asumir que `main` y el binario de Producción son lo mismo.

## Regla innegociable: QA actual + Preview = Producción

Esta regla tiene prioridad sobre cualquier instrucción histórica del repositorio.

### QA siempre certifica la Preview vigente

Antes de ejecutar pruebas funcionales, el workflow `Express QA Auditor` debe:

1. consultar `app_release_gate`;
2. resolver `preview_build_id`, versión, build y SHA vigentes;
3. comprobar que versión/build coinciden con el `pubspec.yaml` actual de `main`;
4. bloquear si existen cambios sensibles de app posteriores al SHA Preview sin una nueva versión/Preview;
5. hacer checkout del SHA exacto de la Preview vigente;
6. probar ese SHA, nunca un tag/build hard-codeado ni una versión antigua.

Un QA verde sobre una Preview vieja NO autoriza Producción.

### Producción siempre es copia exacta de la Preview aprobada

Producción Android debe coincidir simultáneamente en:

- `version_name`;
- `build_number`;
- `commit_sha`;
- Preview vigente y aprobada.

Si cualquiera difiere, el backend y el build worker deben bloquear el release.

Nunca reconstruir Producción desde `main` "parecido" o desde un commit posterior. Producción se compila desde el SHA exacto que fue Preview y fue aprobado.

### Cola de builds

El worker Android debe reclamar primero el build más nuevo. Al reclamar un candidato, los builds pendientes más antiguos del mismo tipo se cancelan como reemplazados.

Está prohibido procesar una cola antigua en orden ascendente y compilar versiones obsoletas antes del candidato actual.

### Protección contra finalización fuera de orden

Si dos Preview terminan fuera de orden, una Preview con `build_number` menor nunca puede reemplazar en `app_release_gate` a una Preview de build mayor ya registrada.

## Regla de release

Producción Android SOLO puede compilarse desde el mismo SHA que fue aprobado como Preview.

Flujo:

`Preview build -> QA -> aprobación -> mismo SHA -> APK/AAB Producción`

No cambiar código después de aprobar un Preview y luego intentar usar ese Preview para Producción.

## APK Preview que se entrega al usuario

Para una Preview instalable con OTA, **solo** distribuir la base Shorebird:

`preview-shorebird-v<VERSION>-build<BUILD>/app-release.apk`

Nunca entregar al usuario final de Preview el artefacto:

`preview-android-v<VERSION>-build<BUILD>/express-preview-...`

Ese segundo APK es un artefacto técnico de compilación/QA y `ShorebirdUpdater.isAvailable` será falso si no fue generado por `shorebird release`.

Antes de compartir un enlace Preview:
1. confirmar que el workflow **Express Preview Shorebird Code Push** terminó en verde en modo `release`;
2. confirmar que existe el tag `preview-shorebird-v<VERSION>-build<BUILD>`;
3. compartir `app-release.apk` de ese tag;
4. después, los cambios Dart compatibles se entregan con **Actualizar cambios** mediante `shorebird patch`.

## Shorebird

Preview puede usar Shorebird.

Si cambia la base nativa o la versión base, se genera una APK Preview nueva. Los siguientes cambios Dart compatibles pueden salir como patch.

Base Preview reciente:

- `1.5.87+131`
- package `com.express.usuario.preview`
- tag `preview-shorebird-v1.5.87-build131`

## Branding

Nombre de marca general: **Express**.

No usar “Express Delivery” como marca global. “Delivery” se conserva solo cuando nombra el módulo/servicio específico de delivery.

Logo oficial:

- asset restaurado/protegido por CI desde `assets/branding/express_app_icon_512.b64`
- widget reutilizable: `lib/express_branding.dart`
- no sustituir por íconos genéricos como `Icons.bolt_rounded`

Splash debe mostrar **Express**.

## Países / moneda

Chile:
- código: `+56`
- moneda: `CLP`
- CLP sin decimales, agrupación estilo `$ 1.583`
- viajes: Efectivo

Bolivia:
- código: `+591`
- moneda: `BOB`
- entero sin `.00`; fracción con 2 decimales
- viajes: Efectivo + QR del conductor

Mercado Pago / pasarelas administrativas NO se usan para el cobro ordinario de viajes. Están reservadas para suscripciones/recargas según configuración.

## Verificación SMS

Existen dos switches independientes administrados desde Adminexpress:

- pasajeros
- conductores

Ambos deben permanecer OFF por defecto hasta configurar proveedor SMS/Twilio.

OFF:
- no enviar OTP
- no bloquear uso
- no exigir teléfono verificado

ON:
- pasajero debe verificar antes de solicitar viaje
- conductor debe verificar antes de conectarse/enviar ofertas
- cuentas existentes no verificadas reciben flujo para verificar/cambiar número

Migraciones relevantes:
- `094_zone_ride_payments_phone_verification.sql`
- `095_sms_verification_admin_switches.sql`

Ambas ya fueron aplicadas al proyecto Express.

## Preview / Producción

El runtime usa `channel`:

- `preview`
- `production`

Nunca permitir que una cuenta QA escriba datos de Producción ni que una cuenta real escriba en Preview.

El backend posee guardas explícitas. No “arreglar” un error de aislamiento eliminando esas guardas.

## Laboratorio QA

Edge Function:

`supabase/functions/express-load-lab/index.ts`

Estado actual:
- separa cleanup por entorno
- Preview crea `channel=preview`
- Producción crea `channel=production`
- Iquique usa CLP
- soporta `service_mode`:
  - `mixed`
  - `car`
  - `motorcycle`
- `mixed` reparte Auto/Moto
- push LOADTEST permanece suprimido

La función desplegada más reciente al 2026-10-04 es la versión 12.

## Visibilidad Auto/Moto

Pasajero:
- `economy` -> vehículo `car`
- `motorcycle` -> vehículo `motorcycle`
- el mapa llama `nearby_online_driver_markers` con filtro de tipo en Producción

Conductor:
- la app filtra solicitudes por su vehículo activo
- Auto no debe recibir solicitudes Moto
- Moto no debe recibir solicitudes Auto

Si Admin muestra solicitudes pero el conductor ve 0, comprobar primero:
1. `ride_requests.category`
2. `driver_vehicles.vehicle_type`
3. zona
4. radio
5. `channel`
6. `same_operational_scope`
7. suscripción/dispatch
8. método de pago aceptado

## QA automático

Workflow: `Express QA Auditor`.

No interpretar automáticamente “rojo” como fallo del producto.

Clasificaciones importantes:
- `confirmed_product_failure`: fallo de producto confirmado
- `qa_infrastructure`: infraestructura/harness
- `qa_inconclusive`: prueba no concluyente
- `healthy`: certificación sana

Último estado conocido al documentar:
- app procesó/compiló bien
- 0 fallos nuevos confirmados de producto
- el auditor sigue bloqueado por problemas del arnés/autenticación de Maestro y credencial visual AI
- no rebajar el gate para hacerlo verde artificialmente

## Seguridad

No guardar en Git:
- service-role keys
- JWT
- contraseñas
- tokens GitHub
- keystore
- passwords de firma
- Twilio secrets
- Mercado Pago secrets

## Regla de cambios

Antes de editar:
1. identificar si el cambio es app, Admin o backend
2. decidir si requiere rebuild o solo deploy backend/web
3. respetar `channel`
4. ejecutar análisis/build
5. probar Preview
6. documentar

Cambios solo Edge Function/Supabase pueden no requerir APK nueva.
Cambios Dart que afectan app sí requieren Preview nuevo o patch Shorebird compatible.

## No hacer

- no copiar Adminexpress dentro de Expressdelivery
- no cambiar package ID
- no regenerar firma Android
- no saltarse release gate
- no activar SMS por defecto
- no usar QR administrativo para cobro de viaje
- no mezclar datos Preview/Producción
- no reemplazar logo oficial
- no asumir que 100 solicitudes QA deben mostrarse a cualquier conductor; deben coincidir tipo, zona, radio y entorno
