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

- misma versión;
- mismo build number;
- mismo SHA;
- mismo `lib/mobile_main.dart`;
- mismo código funcional.

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

### Paso 6 — Aprobación

Solo después de QA puede aprobarse el Preview.

### Paso 7 — Producción

Producción hace checkout del SHA certificado y compila:

- target: `lib/mobile_main.dart`;
- `EXPRESS_PREVIEW_MODE=false`;
- package Producción;
- APK + AAB.

No se permite introducir código entre QA y build Producción.

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
