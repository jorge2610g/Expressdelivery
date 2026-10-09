> **ACTUALIZACIÓN 2026-10-08 — PROYECTOS SUPABASE SEPARADOS (EN RAMA; NO DESPLEGADO):** la regla antigua de cambio Preview/Production por cuenta dentro del mismo proyecto queda reemplazada por backends separados. El paquete Preview debe apuntar exclusivamente a `xbphilqezmwfjfpdbwad`; Producción sigue en `zgpijrznvaskgcmauwxx`. No migrar cuentas; mismo SHA funcional con credenciales de ambiente diferentes. Push Preview está bloqueado hasta Firebase/VAPID/origen exclusivos. Ver `docs/ISOLATED_SUPABASE_PUSH_ENVIRONMENTS.md`.

> **ACTUALIZACIÓN 2026-10-08 — decisión posterior a +163:** consultar primero `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`. El flujo cotidiano ya no genera APK Preview por cada cambio: Web primero; Android nativo solo a petición. La arquitectura del gate de publicación descrita debajo sigue como legado temporal para Producción y NO ha sido migrada.

# Arquitectura Preview → Producción de Express

> **Estado:** AUTORITATIVO desde Android **1.6.0+163**  
> **Fecha:** 2026-10-06  
> **Repo:** `jorge2610g/Expressdelivery`  
> **Objetivo:** impedir que Preview y Producción vuelvan a comportarse como dos aplicaciones funcionalmente distintas.

---

## 1. Regla principal

**Preview NO es otra aplicación funcional.**

Preview y Producción son dos configuraciones del **mismo código móvil**, del **mismo entrypoint** y, al promover una release, del **mismo commit SHA**.

La cadena obligatoria es:

`mismo código -> mismo SHA -> Preview -> QA -> certificado -> Producción desde ese mismo SHA`

Producción **no copia manualmente archivos desde Preview** y tampoco reconstruye una variante lógica distinta. Se recompila el mismo commit certificado cambiando solo configuración explícita de entorno/empaquetado.

---

## 2. Por qué se cambió la arquitectura

Antes de +163 existían dos caminos de arranque:

- Preview: `lib/preview_main.dart`
- Producción: `lib/mobile_main.dart`

Aunque ambos reutilizaban muchas pantallas y servicios, cada archivo ejecutaba su propio `main()` y podía inicializar auth, Supabase, servicios nativos o almacenamiento de forma distinta.

Consecuencia demostrada:

- Preview podía abrir y funcionar;
- Producción podía fallar al iniciar;
- las pruebas manuales de Preview no certificaban realmente el camino de arranque que usaría Producción;
- el equipo terminaba haciendo dos ciclos de prueba y dos esperas de compilación.

Los fallos físicos de Producción +158/+159 hicieron visible este defecto de arquitectura.

**Decisión:** desde +163 no se permiten dos caminos funcionales de startup.

---

## 3. Entry point móvil autoritativo

### Único entrypoint de release

`lib/mobile_main.dart`

Este archivo contiene:

- `main()`;
- `runExpressMobile(...)`;
- bootstrap compartido;
- montaje de `ExpressMobileApp`;
- selección de comportamiento Preview/Producción mediante configuración.

### Wrapper histórico/compatibilidad

`lib/preview_main.dart`

Puede existir como wrapper mínimo para herramientas locales, pero:

- **NO contiene lógica de startup propia**;
- **NO inicializa Supabase por separado**;
- **NO inicializa servicios nativos por separado**;
- **NO es target de Shorebird**;
- **NO es target del QA Android**;
- **NO es target del builder oficial Android**.

Si una IA vuelve a agregar lógica funcional a `preview_main.dart`, está reintroduciendo el defecto que +163 elimina.

---

## 4. Cómo se distingue Preview de Producción

El mismo `lib/mobile_main.dart` se compila con configuración diferente.

### Preview

- `EXPRESS_PREVIEW_MODE=true`
- package: `com.express.usuario.preview`
- Firebase/configuración Android correspondiente a Preview
- runtime channel: `preview`
- herramientas/overlay QA permitidos
- APK solamente
- Shorebird habilitado para el circuito Preview

### Producción

- `EXPRESS_PREVIEW_MODE=false`
- package: `com.express.usuario1`
- Firebase/configuración Android correspondiente a Producción
- runtime channel: `production`
- herramientas QA ocultas
- APK + AAB

La variable de entorno cambia configuración. **No debe seleccionar otra implementación funcional de Express.**

---

## 4.1 Internal Testing con resolución de entorno por cuenta (+165 experimental)

Para evitar certificar un APK Preview y después descubrir una diferencia nativa en Producción, se prueba de forma controlada este modelo:

- el APK Preview existente permanece estricto y aislado;
- el AAB candidato sigue siendo físicamente Producción (`com.express.usuario1`);
- después del login, Supabase puede resolver una cuenta QA ya autorizada a `preview`;
- cuentas normales siempre permanecen en `production`;
- el usuario no puede elegir el entorno desde la interfaz;
- el canal resuelto alimenta la misma lógica existente de viajes, wallet, pagos, suscripciones, pricing y configuraciones por zona;
- la certificación final debe ocurrir sobre el AAB real en Google Play Internal Testing;
- si QA pasa, se promueve el mismo artefacto; no se recompila.

Este experimento no elimina el package Preview ni modifica Producción pública hasta aprobación explícita.

## 5. Diferencias permitidas

Estas diferencias son esperadas y no significan que sean dos productos distintos:

- package/application ID;
- nombre visible `Express Preview` vs `Express`;
- cliente Firebase asociado al package;
- runtime channel `preview` / `production`;
- overlay y herramientas exclusivas de QA;
- actualización Shorebird/controles de Preview;
- update gate o controles propios de la distribución de Producción;
- cuentas y datos permitidos por el aislamiento de entorno;
- firma/artefacto Android;
- APK-only en Preview vs APK+AAB en Producción.

Toda diferencia nueva debe documentarse aquí y justificar por qué es configuración de entorno y no una segunda lógica de producto.

---

## 6. Diferencias PROHIBIDAS

Preview y Producción no pueden tener implementaciones distintas para:

- bootstrap Supabase;
- persistencia/restauración de sesión;
- login/registro/recuperación de contraseña;
- navegación principal;
- Pasajero/Conductor;
- creación de solicitudes;
- ofertas y contraofertas;
- selección de conductor;
- estados del viaje;
- llegada y espera;
- PIN;
- inicio/finalización;
- cancelación;
- mapas/rutas;
- llamadas privadas;
- rating Pasajero ↔ Conductor;
- pricing;
- historial;
- lógica de notificaciones;
- reglas de disponibilidad;
- seguridad de producto.

Puede cambiar una credencial/configuración de entorno, pero no la lógica que consume esa configuración.

**No copiar y pegar una función en una variante Preview y otra Producción. Debe existir una sola implementación compartida.**

---

## 7. Bootstrap compartido

Auth/Supabase usa:

`lib/core/express_supabase_bootstrap.dart`

Preview y Producción pasan por el mismo bootstrap.

Los servicios opcionales no deben bloquear el montaje inicial. Un fallo de push, llamadas u otro servicio secundario no debe transformar una app funcional en `Express no pudo iniciar`.

Si se modifica startup:

1. modificar el camino compartido;
2. probar Preview;
3. ejecutar smoke con configuración Producción;
4. nunca aplicar un fix solo a Producción o solo a Preview salvo que sea estrictamente una diferencia de configuración documentada.

---

## 8. Regla de SHA

QA certifica **un commit exacto**, no “el código más reciente” ni “algo parecido”.

Ejemplo conceptual:

`ABC123 -> Preview -> QA healthy -> certificar ABC123 -> Producción checkout ABC123`

Producción debe usar:

- mismo `version_name` funcional;
- **mismo SHA**;
- mismo `lib/mobile_main.dart`;
- mismo código funcional;
- **build numbers independientes**: Preview y Producción no comparten contador.

Un commit posterior que cambie `lib/**`, dependencias, assets/runtime o configuración sensible requiere una nueva Preview y nueva certificación.

### Commits solo documentales

Es válido que `main` avance por cambios exclusivos en `docs/**` o `AGENTS.md` mientras un candidato está compilando.

Eso **no cambia el SHA del código ya certificado**. Producción debe seguir haciendo checkout del SHA exacto registrado en el gate, no del HEAD documental más nuevo.

---

## 9. Flujo obligatorio de promoción

### Paso 1 — Código

Se implementa el cambio en la única base compartida.

### Paso 2 — Candidato Preview

Se incrementa build y Shorebird genera Preview desde:

- target: `lib/mobile_main.dart`;
- `EXPRESS_PREVIEW_MODE=true`.

### Paso 3 — Identidad

Release, manifiesto, versión, build, SHA y `app_release_gate` deben coincidir.

### Paso 4 — QA obligatorio

QA audita ese SHA exacto.

Debe validar, como mínimo:

- arranque Preview;
- arranque del **mismo entrypoint** con configuración Producción;
- login/superficie funcional;
- solicitud;
- oferta;
- aceptación;
- conductor en camino;
- llegada;
- PIN;
- viaje;
- finalización;
- calificación pendiente de Pasajero;
- calificación pendiente de Conductor;
- persistencia de ambas calificaciones.

### Paso 5 — Certificado QA

El gate debe registrar para el Preview vigente:

- `qa_preview_build_id`;
- `qa_commit_sha`;
- `qa_workflow_run_id`;
- `qa_passed_at`.

Todos deben corresponder al mismo candidato.

### Paso 6 — Candidato Producción precompilado

Antes de terminar la aprobación manual se genera desde el **mismo SHA**:

- APK Producción;
- AAB Producción;
- package `com.express.usuario1`;
- `EXPRESS_PREVIEW_MODE=false`;
- build number Producción independiente.

Se registra como `candidate-apk+aab` y todavía no se publica en Play.

### Paso 7 — Aprobación

Solo después de QA puede aprobarse Preview.

### Paso 8 — Promoción sin recompilar

Si Preview pasa, se promueven los **mismos APK/AAB ya generados**. No se recompila después de aprobar.

---

## 10. Qué significa “probar Producción”

La prueba manual fuerte se hace en Preview porque contiene el mismo código funcional.

Producción mantiene un smoke automático porque sí existen diferencias inevitables de empaquetado/configuración:

- package;
- Firebase;
- manifest;
- firma;
- recursos;
- permisos/configuración nativa.

Ese smoke **no significa volver a desarrollar o volver a probar otra aplicación**. Su función es confirmar que el empaquetado Producción no rompe el mismo código ya certificado.

Si el smoke Producción falla:

- NO reparar una rama Producción separada;
- localizar la diferencia de configuración/empaquetado;
- corregir la base compartida o el builder;
- generar un candidato nuevo si cambia código funcional.

---

## 11. Gate de release

Producción no puede crearse si falta cualquiera de estas condiciones:

- Preview Shorebird vigente;
- versión/build válidos;
- SHA exacto;
- QA certificado sobre ese mismo Preview/SHA;
- aprobación posterior al QA;
- job Producción usando exactamente ese SHA.

No insertar manualmente un build Producción para saltar el gate.

---

## 12. Qué debe revisar una IA antes de tocar Android

Antes de cualquier cambio de release:

1. leer `AGENTS.md`;
2. leer este documento;
3. leer `docs/AI_HANDOFF_2026-10-06_MASTER.md`;
4. revisar `pubspec.yaml`;
5. revisar `lib/mobile_main.dart`;
6. comprobar que `lib/preview_main.dart` sigue siendo wrapper sin startup propio;
7. buscar cualquier workflow que todavía use `--target lib/preview_main.dart`;
8. revisar `app_release_gate`;
9. revisar último workflow Shorebird;
10. revisar último QA;
11. no declarar Producción lista solo porque compiló.

Comando conceptual de auditoría:

`grep/search "lib/preview_main.dart" en workflows`

Una referencia documental es válida. Un `--target lib/preview_main.dart` en un builder oficial es una regresión arquitectónica.

---

## 13. Regla para fixes

Si algo funciona en Preview y falla en Producción:

**NO asumir inmediatamente que “Producción tiene otro código”.**

Primero comprobar:

- package/config Firebase;
- manifest;
- firma;
- SharedPreferences por package;
- permisos Android;
- recursos;
- variables `--dart-define`;
- servicios externos configurados por package;
- diferencias nativas del builder.

La solución debe preservar una única lógica funcional.

---

## 14. Regla de CI

Los workflows oficiales deben respetar:

- Preview Shorebird target = `lib/mobile_main.dart`;
- QA Preview target = `lib/mobile_main.dart`;
- QA Production-mode target = `lib/mobile_main.dart`;
- Production APK target = `lib/mobile_main.dart`;
- Production AAB target = `lib/mobile_main.dart`.

Flags:

- Preview: `EXPRESS_PREVIEW_MODE=true`;
- Producción: `EXPRESS_PREVIEW_MODE=false`.

Cualquier workflow nuevo debe seguir la misma regla.

---

## 15. Candidato de transición +163

Primer candidato creado después de unificar el entrypoint:

- versión: `1.6.0+163`;
- SHA de código candidato: `a3006e4d703e8ac12c87ccf74abc0fb068fd2999`;
- workflow Shorebird inicial: run `#387`;
- Preview y Producción usan `lib/mobile_main.dart`;
- +162 pertenece al proceso anterior y no debe promoverse.

Los commits documentales posteriores no reemplazan este SHA como identidad del candidato.

+163 solo podrá ir a Producción si Shorebird publica correctamente, QA certifica exactamente este SHA y el release gate permite la aprobación.

---

## 16. Regla de continuidad

Para cualquier IA futura:

> **No existen “código Preview” y “código Producción” como dos implementaciones. Existe código Express y dos configuraciones de distribución.**

Si una tarea parece requerir duplicar una función para Preview y Producción, detenerse y revisar la arquitectura antes de hacerlo.

---

## 17. Contadores independientes

**Regla obligatoria:** el vínculo Preview → Producción es el SHA, no el build number.

- Preview avanza con su contador de pruebas: 163, 164, 165...
- Producción/Google Play avanza con su propio versionCode: 132, 133, 134...
- APK y AAB de una misma Producción sí comparten el mismo build number.
- Preview y Producción deben compartir `version_name`, SHA y código funcional.

Estado informado por el propietario al 2026-10-06:

- Play Store Producción: build/versionCode 131.
- Preview actual: build 163.
- siguiente candidato Producción: build 132.

Ejemplo válido:

`Preview 1.6.0+163` + `Producción APK/AAB 1.6.0+132` + **mismo SHA**.

Si Play Console ya hubiese consumido un versionCode mayor en otro track/draft, solo se incrementa el contador Producción. No se altera Preview ni el SHA funcional.


### 17.1 Regla obligatoria de versionado para Google Play

Para toda publicación Android en Producción se deben tratar como conceptos distintos:

- `versionName`: versión funcional/comercial visible, por ejemplo `1.6.0`, `1.6.1`, `1.7.0`.
- `versionCode` / build: identificador técnico entero que Google Play exige que sea único y creciente.

Reglas obligatorias:

1. **Nunca reutilizar un `versionCode` que Google Play haya recibido antes**, aunque esa versión esté inactiva, en otra pista, en prueba, retirada o en borrador.
2. Antes de crear un nuevo AAB, revisar en Play Console el **mayor `versionCode` ya usado** para `com.express.usuario1`.
3. El siguiente candidato de Producción debe usar un `versionCode` mayor al máximo usado en Play.
4. El contador Preview es independiente y **no se usa para decidir el `versionCode` de Google Play**.
5. APK y AAB de un mismo candidato de Producción deben compartir exactamente el mismo `versionName`, `versionCode`, SHA y firma.
6. Si solo se incrementa el `versionCode` por una colisión de Play y no cambia el código funcional, el `versionName` puede mantenerse.
7. El `versionName` solo debe cambiar cuando se decida una nueva versión funcional/comercial.
8. El release gate y la documentación deben registrar por separado:
   - Preview build;
   - Production/Play `versionCode`;
   - `versionName`;
   - commit SHA.
9. Fuente de verdad para saber qué códigos ya fueron consumidos: **Google Play Console**. Los contadores internos del proyecto son auxiliares y no pueden reemplazar esa comprobación.

Ejemplo:

`Preview 1.6.0+165` puede promoverse como `Producción 1.6.0+166` si `166` es mayor que cualquier `versionCode` ya usado en Play y ambos artefactos provienen del mismo SHA certificado.


## 18. Prebuild de Producción

La espera debe solaparse:

`Preview APK N + Production Candidate APK M + Production Candidate AAB M`

se generan desde el mismo SHA antes de la aprobación manual.

Si Preview falla y M nunca fue subido a Play, M puede reutilizarse con la siguiente Preview corregida.

Si Preview pasa QA y es aprobada, el candidato M se promueve **sin recompilar**.

Backend relacionado:

- `build_jobs.artifact_type = candidate-apk+aab`;
- `app_release_gate.next_production_build_number`;
- `app_release_gate.production_candidate_*`;
- `admin_promote_production_candidate(uuid)`;
- migración `127_independent_preview_production_build_numbers.sql`.
## 16. Gate automático de trazabilidad y contador Google Play · 2026-10-07

La trazabilidad de Producción ya no depende de revisar manualmente el nombre del APK/AAB.

Reglas autoritativas:

- `production_store_build_number` representa el último versionCode de Producción confirmado por el circuito de promoción;
- `next_production_build_number` es derivado y siempre debe ser `production_store_build_number + 1`;
- baseline corregido: **137**, por lo que el candidato vigente debe ser **138**; después de promover 138 el siguiente pasa automáticamente a **139**, luego 140, etc.;
- Preview, Shorebird y builds internos nunca pueden avanzar el contador Google Play;
- un candidato Producción solo compila si su versión + SHA coinciden exactamente con la Preview vigente;
- antes de compilar, CI compara el SHA candidato contra `main` en rutas móviles sensibles; si existe código móvil más nuevo, el build se bloquea;
- el contrato de release exige perfil con correo+teléfono+versión visible, Mapbox, anuncios de Pasajero y entrypoint móvil compartido;
- después de compilar, CI lee el manifiesto real del APK y exige package, versionName y versionCode exactos;
- APK/AAB publican un archivo `*-identity.json` con SHA fuente, tree SHA, SHA de main observado, workflow y SHA-256 de artefactos;
- el worker revalida el gate al finalizar; si Preview/gate cambió durante la compilación, el candidato no se marca READY;
- los candidatos 166 generados por la deriva anterior quedan invalidados y no son promovibles.

