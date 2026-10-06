# Express — Handoff autoritativo de release, trazabilidad y documentación

> **Fecha de corte:** 2026-10-05 (America/Santiago) / 2026-10-06 UTC  
> **Repositorio:** `jorge2610g/Expressdelivery`  
> **Estado:** documento autoritativo para cualquier IA, agente o desarrollador que continúe el trabajo.
>
> Si este archivo contradice documentación histórica anterior, **este archivo prevalece para Preview, Shorebird, QA, release gate y reglas de documentación**.

---

## 1. Regla principal: no confiar en el nombre del run

En Express, un nombre como `1.6.0+151` NO demuestra por sí solo que la APK, el SHA, el release y el gate correspondan realmente a `1.6.0+151`.

La identidad real de una release está compuesta por:

1. `version_name`
2. `build_number`
3. `commit_sha`
4. APK/AAB realmente generados
5. tag/release que contiene esos artefactos
6. `app_release_gate`
7. workflow que los produjo
8. QA que certificó exactamente esa misma identidad

**Todos deben coincidir.**

Si uno difiere, la release se considera **NO certificada** aunque GitHub Actions muestre verde.

---

## 2. Estado exacto al crear este documento

### Código actual

- candidato Preview: **1.6.0+151**
- SHA de app que está construyendo la base +151:
  `cb588ae43f81e77152078e0d65f225ced7928dc1`
- `main` actual después de corregir el disparo del auditor:
  `c8f3ba3c8b7042ef9b010e87b541faf15e3c6499`
- diferencia entre ambos SHA:
  - solo `.github/workflows/express-qa.yml`
  - no cambió `lib/`
  - no cambiaron assets
  - no cambió Android
  - no cambiaron dependencias

Por lo tanto, el código de app que entra en **+151 sí corresponde al código de aplicación actual**. No es una +150 renombrada.

### Shorebird

Workflow:

- **Express Preview Shorebird Code Push**
- run: **#344**
- run id: `37405018729`
- SHA: `cb588ae43f81e77152078e0d65f225ced7928dc1`
- objetivo: crear base limpia **1.6.0+151**
- modo esperado: **release**
- Preview debe publicar **APK solamente**
- al momento de este documento: **in_progress**

No considerar +151 lista hasta confirmar:

- run terminado en success;
- tag `preview-shorebird-v1.6.0-build151`;
- `app-release.apk` existente;
- identidad del gate actualizada a +151;
- SHA del gate correcto.

### Release gate actualmente observado

El gate seguía apuntando a:

- Preview: **1.6.0+150**
- build id: `14ce83d9-9416-48db-a404-a8c923d25c98`
- base SHA: `473c5ca1d25203b609d4d3795f8399bad54afae1`
- current SHA: `473c5ca1d25203b609d4d3795f8399bad54afae1`
- patch workflow: null
- patch at: null
- Preview aprobada: null

Esto explica por qué un QA disparado durante la construcción de +151 encontró todavía +150.

### QA inválido observado

Workflow:

- **Express QA Auditor**
- run: **#728**
- run id: `37405018948`
- event: `push`
- commit visible: +151

Error real:

`QA bloqueado: main declara 1.6.0+151 pero la Preview vigente es 1.6.0+150.`

Ese run:

- **NO probó la APK +151**
- **NO es un fallo funcional de la app**
- se detuvo antes de construir/ejecutar la prueba
- demuestra una carrera de pipeline entre `push` y publicación Shorebird

### Build Android verde que no construyó nada

Run:

- **Build Express Android #669**
- run id: `37405018718`
- conclusión GitHub: `success`

Pero el propio workflow indicó:

`No hay builds Android en cola.`

Por tanto:

**un workflow verde sin artefacto generado NO cuenta como build válido ni como certificación.**

---

## 3. Causa raíz de los fallos recientes

Hubo varias clases de fallo diferentes y no deben mezclarse.

### A. +150: fallo de arranque

La base +150 salió con un problema al iniciar relacionado con el canal nativo de `shared_preferences_android` durante la inicialización/sesión de Preview.

Se corrigió `lib/preview_main.dart` para que Preview no dependa de ese almacenamiento durante el arranque y mantenga el storage de auth en memoria.

Esto NO borró Supabase ni la base de datos.

### B. Patch de +150: Shorebird rechazó diferencias nativas

Se intentó llevar el arreglo a la base +150 mediante patch.

Shorebird rechazó el patch por diferencias nativas en DEX/clases, incluyendo componentes de:

- ZEGO
- Firebase
- Didit
- Kotlin
- GeneratedPluginRegistrant

No se debe forzar este caso con `--allow-native-diffs` solo para lograr verde.

Regla oficial:

- si el cambio es parcheable y Shorebird lo acepta -> patch;
- si Shorebird detecta incompatibilidad nativa -> **crear nueva base Preview APK limpia**.

Por eso se creó el candidato **1.6.0+151**.

### C. Auditor disparado demasiado pronto

El auditor tenía dos disparadores relevantes:

- `push`
- `workflow_run` después de Shorebird

Eso permitía:

1. push de +151;
2. QA arrancando inmediatamente;
3. Shorebird todavía construyendo +151;
4. gate todavía en +150;
5. QA fallando por identidad cruzada.

Se corrigió el workflow para que el QA automático de cambios de app **no se dispare por push**.

Commit de corrección:

`c8f3ba3c8b7042ef9b010e87b541faf15e3c6499`

Mensaje:

`ci: audit Preview only after published Shorebird build`

Después de ese commit no se disparó otro QA por `push`, confirmando que la carrera quedó cortada en ese punto.

---

## 4. Flujo obligatorio correcto

### Preview

Flujo oficial:

`cambio -> documentación -> versión/build -> Shorebird release/patch -> artefacto -> release/tag -> gate -> QA -> aprobación`

Nunca invertir ese orden.

### Nueva base Preview

Cuando se necesita base nueva:

1. fijar versión/build en `pubspec.yaml`;
2. fijar SHA fuente;
3. construir con Shorebird;
4. generar **APK únicamente**;
5. publicar tag `preview-shorebird-v<VERSION>-build<BUILD>`;
6. confirmar `app-release.apk`;
7. registrar la misma identidad en `app_release_gate`;
8. recién entonces disparar QA;
9. QA debe comprobar:
   - versión;
   - build;
   - SHA;
   - release/tag;
   - APK;
   - gate;
10. solo después puede marcarse certificada.

### Patch Shorebird

Antes de patch:

1. confirmar base activa real;
2. confirmar que versión/build coinciden;
3. confirmar que el cambio es compatible con patch;
4. intentar patch sin permitir diferencias nativas peligrosas;
5. si falla por native diffs:
   - NO insistir;
   - NO falsear identidad;
   - crear nueva base APK Preview.

### Producción

Regla oficial:

**Preview validada -> misma identidad -> Producción**

Producción Android:

- genera **APK + AAB**
- debe usar exactamente:
  - mismo `version_name`;
  - mismo `build_number`;
  - mismo SHA aprobado;
- no reconstruir desde un `main` posterior “parecido”.

Preview:

- **APK solamente**
- nunca AAB.

---

## 5. Gate de trazabilidad obligatorio

Antes de considerar una release válida se deben responder afirmativamente estas preguntas:

- ¿`pubspec.yaml` declara la versión esperada?
- ¿el SHA compilado es el esperado?
- ¿el workflow compiló realmente y no terminó vacío?
- ¿existe el artefacto?
- ¿el APK pertenece a ese SHA?
- ¿el tag/release corresponde a esa versión/build?
- ¿el gate apunta a esa misma versión/build/SHA?
- ¿QA hizo checkout de ese SHA?
- ¿QA probó esa identidad y no una anterior?
- ¿el resultado QA corresponde a ese mismo build?

Si una sola respuesta es “no”, “no sé” o “todavía no”:

**NO promover, NO declarar listo y NO usar el verde del workflow como evidencia suficiente.**

---

## 6. Regla de documentación 100% obligatoria

Esta regla es oficial y permanente.

### Toda modificación se documenta

Debe documentarse cualquier cambio, sin importar tamaño:

- una línea;
- texto;
- UI;
- lógica;
- dependencia;
- configuración;
- workflow;
- Supabase;
- Edge Function;
- migración;
- QA;
- release;
- versión;
- build;
- fix;
- eliminación;
- rollback;
- feature flag;
- permiso;
- branding;
- credencial/configuración externa sin exponer secretos.

### Cuándo

La documentación debe quedar:

- idealmente en el mismo commit;
- o en un commit documental inmediatamente asociado;

pero **antes de considerar el trabajo terminado o promoverlo a otra etapa**.

### Un cambio sin documentación está incompleto

Regla:

> **CODE CHANGED = DOCS MUST CHANGE**

Si se tocó código/configuración/release y no existe actualización documental asociada:

- el trabajo sigue abierto;
- no se declara terminado;
- no se promueve a Preview/Producción;
- la siguiente IA debe documentarlo antes de continuar.

### Archivos mínimos a actualizar

Para cualquier cambio relevante:

1. `docs/CHANGELOG_ACTIVE.md`
2. este handoff si afecta estado, arquitectura, releases, QA o reglas
3. `docs/START_HERE_EXPRESS.md` si cambia el punto de entrada o estado general
4. documentación específica del módulo cuando aplique

### Datos mínimos por entrada documental

Registrar como mínimo:

- fecha;
- objetivo;
- qué cambió;
- qué se eliminó;
- archivos/componentes afectados;
- versión/build;
- SHA cuando exista;
- Preview o Producción;
- si requiere rebuild o patch;
- estado QA;
- riesgo/limitación pendiente;
- instrucciones para continuar;
- qué NO hacer.

---

## 7. Regla para cualquier IA que entre al repositorio

Antes de editar:

1. leer `AGENTS.md`;
2. leer este archivo completo;
3. leer `docs/CHANGELOG_ACTIVE.md`;
4. comprobar `pubspec.yaml`;
5. comprobar `main` actual;
6. comprobar últimos workflows;
7. comprobar gate si el trabajo toca Android release;
8. comparar documentación contra realidad antes de asumir estado.

La IA NO debe:

- confiar en memorias de conversaciones como única fuente;
- confiar en el nombre visible de un workflow;
- asumir que `main` = APK publicada;
- asumir que verde = artefacto válido;
- cambiar solamente el número de versión para “hacer coincidir” una release;
- reutilizar una APK vieja bajo un nombre nuevo;
- certificar una Preview distinta a la publicada;
- saltarse documentación porque el cambio “es pequeño”.

---

## 8. Regla de borrados y reemplazos

Cuando algo se elimina o reemplaza, documentar explícitamente:

- qué se eliminó;
- por qué;
- qué lo sustituye;
- desde qué versión/build;
- si requiere migración o compatibilidad;
- si queda código legado.

No basta con documentar “se agregó X”.

Esto evita que otra IA restaure accidentalmente código viejo pensando que “falta”.

---

## 9. Regla para fallos de QA

No interpretar un rojo automáticamente como bug de producto.

Clasificar primero:

- `confirmed_product_failure`
- `qa_infrastructure`
- `qa_inconclusive`
- identidad/versionado incorrecto
- build inexistente
- gate atrasado
- race condition de CI
- error real de compilación

Si QA se detiene antes de ejecutar la app por versión/SHA/gate:

**no es evidencia de fallo funcional.**

---

## 10. Regla para “verde”

Un verde solo es útil si demuestra trabajo real.

No cuenta como build válido si:

- no reclamó job;
- no compiló;
- no generó APK/AAB;
- no publicó artefacto;
- no actualizó gate cuando correspondía.

Siempre revisar steps/logs y artefactos.

---

## 11. Convenciones permanentes de artefactos

### Preview

- APK: sí
- AAB: **no**
- Shorebird base APK para instalación
- patches cuando sean compatibles

### Producción

- APK: sí
- AAB: sí
- misma identidad aprobada de Preview

Nunca generar AAB Preview salvo que una regla futura explícita reemplace esta política y quede documentada.

---

## 12. Estado de acciones pendientes al cierre

Pendiente verificar la base **1.6.0+151**:

- que Shorebird #344 termine;
- que exista release/tag +151;
- que exista APK;
- que gate pase de +150 a +151;
- que el SHA del gate sea correcto;
- que QA se dispare únicamente después;
- que QA pruebe +151;
- que el resultado sea funcional y trazable.

Hasta entonces:

- +151 es el candidato correcto;
- todavía no está certificada;
- +150 sigue siendo la identidad observada en el gate;
- Producción no debe tocarse por este flujo.

---

## 13. Checklist de cierre de cualquier tarea futura

Antes de decir “listo”:

- [ ] cambio implementado
- [ ] código revisado
- [ ] versión/build correctos
- [ ] SHA identificado
- [ ] documentación actualizada
- [ ] changelog actualizado
- [ ] build real ejecutado si aplica
- [ ] artefacto real verificado
- [ ] tag/release verificado
- [ ] gate verificado
- [ ] QA de la misma identidad
- [ ] Producción no tocada sin autorización
- [ ] pendientes/limitaciones documentados

Si falta una casilla aplicable, la tarea **no está cerrada**.
