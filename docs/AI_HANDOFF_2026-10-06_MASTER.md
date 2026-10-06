# Express — Handoff maestro para continuidad con IA

> **Fecha de corte:** 2026-10-06 (America/Santiago)  
> **Repositorio:** `jorge2610g/Expressdelivery`  
> **Propósito:** permitir que otra IA, agente o desarrollador continúe Express sin depender de conversaciones anteriores.
>
> **Este documento es la puerta de entrada autoritativa vigente.** Si contradice un handoff anterior, prevalece este archivo para estado actual, reglas operativas, release, QA y continuidad.

---

## 0. Cómo interpretar este documento

Cada punto usa una de estas categorías:

- **REGLA:** decisión obligatoria del producto o del proceso. No cambiarla sin instrucción explícita del propietario y sin documentar el reemplazo.
- **CONFIRMADO:** comportamiento o implementación verificada en código/workflows/backend.
- **PENDIENTE DE VALIDAR:** requisito solicitado o cambio en curso que no debe darse por terminado sin evidencia.
- **HISTÓRICO:** referencia útil, pero no fuente vigente cuando existe una regla más nueva.

Regla permanente:

> **NO asumir que “pedido” = “implementado”. NO asumir que “workflow verde” = “release válido”.**

---

## 1. Lectura obligatoria para cualquier IA nueva

Orden de lectura:

1. `AGENTS.md`
2. **este archivo**
3. `docs/DOCUMENTATION_POLICY.md`
4. `docs/CHANGELOG_ACTIVE.md`
5. `docs/START_HERE_EXPRESS.md`
6. `docs/QA_AUTOMATION.md`
7. `docs/PRIVATE_VOICE_CALLS.md`
8. `docs/PHONE_OTP_ROUTER.md`
9. `docs/GOOGLE_PLAY_SUBMISSION.md`
10. documentación específica del módulo que se vaya a tocar

Los handoffs del 2026-10-04 y 2026-10-05 quedan como **historial técnico** y evidencia de decisiones anteriores.

---

## 2. Identidad y arquitectura del producto

### 2.1 Producto

- Marca general: **Express**.
- App Flutter unificada para **Pasajero + Conductor**.
- Express Delivery puede convivir como módulo, pero el panel administrativo no vive dentro de esta app.
- El panel administrativo es otro proyecto:
  - repo: `jorge2610g/Adminexpress`
  - web conocida: `admin.expressviajes.online`

### 2.2 Backend correcto

Supabase Project Ref oficial de Express:

`zgpijrznvaskgcmauwxx`

**REGLA:** nunca ejecutar migraciones, Edge Functions o cambios de Express en otro proyecto Supabase.

### 2.3 Entradas principales

- Producción Android: `lib/mobile_main.dart`
- Preview Android: `lib/preview_main.dart`
- Web: `lib/web_preview.dart`

Package IDs:

- Producción: `com.express.usuario1`
- Preview: `com.express.usuario.preview`

### 2.4 Cuenta única

**REGLA de producto:**

- una persona tiene una sola identidad Express;
- inicia como Pasajero;
- “Conducir con Express” añade/completa el perfil de conductor usando el mismo `user_id`;
- `active_mode` selecciona experiencia Pasajero o Conductor;
- un conductor no debe necesitar otra cuenta/correo para cambiar de modo;
- el modo Conductor requiere perfil/vehículo/documentación y aprobación cuando corresponda.

---

## 3. Estado Android vigente al 2026-10-06

### 3.1 Última base instalada/verificada anteriormente

Preview Shorebird:

- versión: **1.6.0+151**
- tag: `preview-shorebird-v1.6.0-build151`
- APK: `app-release.apk`
- SHA de base que quedó registrado: `cb588ae43f81e77152078e0d65f225ced7928dc1`

### 3.2 Fallo manual detectado en +151

**CONFIRMADO:** durante un viaje real de prueba, el botón **Llamar** de la tarjeta principal abría el selector Android de aplicaciones externas (Teléfono/Zoom) en vez de la llamada privada ZEGOCLOUD.

Causa:

- `video_style_home.dart` todavía llamaba `callExpressNumber(...)`;
- esa ruta generaba un URI `tel:`;
- no se ejecutaba `zego-call prepare`;
- no se creaba fila en `private_voice_calls`.

Fix de app:

`df5959499e58cdf258372baa81e2321fd3e3e32b`

Guard QA contra regresión:

`169a32387c6101a8b7169018d941d3c6dcf7e9f9`

### 3.3 Patch fallido y decisión segura

El patch Shorebird del fix fue rechazado porque Shorebird detectó cambios nativos/DEX, incluyendo ZEGO, Firebase Messaging, Didit y clases Android.

**REGLA:** no usar `--allow-native-diffs` para “hacerlo pasar” si no se entiende y demuestra que es seguro.

Decisión:

- no forzar patch;
- crear nueva base Preview.

### 3.4 Candidato actual

Preview:

- versión: **1.6.0+153**
- SHA fuente de la app: `b0093637d363ed3e19b38fc5ab206502bb79976e`
- APK Shorebird publicado como `preview-shorebird-v1.6.0-build153/app-release.apk`;
- identidad fuerte del artefacto: `preview-build-identity.json`, que contiene versión, build, SHA fuente, run de build y SHA-256 del APK;
- release gate recuperado y registrado sobre el SHA fuente `b0093637d363ed3e19b38fc5ab206502bb79976e`;
- QA manual de recuperación lanzado sobre esa identidad;
- Producción: **sin cambios**.

### 3.5 Incidente de identidad detectado en +152

+152 sí compiló y publicó APK, y el gate quedó correctamente en el SHA de build `c5f397c8ce617b97fb1f3b723f38c6b00c6835c3`.

Sin embargo, el tag GitHub `preview-shorebird-v1.6.0-build152` quedó apuntando al commit documental más reciente porque `gh release create` no llevaba una identidad verificable separada del movimiento de `main`.

QA bloqueó correctamente porque:

- gate/base SHA: `c5f397c8ce617b97fb1f3b723f38c6b00c6835c3`
- tag SHA observado: `fc47121cce8206ec38b1e8ff43baa0e1e74a7c9d`

Corrección permanente:

- +152 no se considera certificada;
- se creó +153 para obtener una identidad limpia;
- se comprobó que GitHub rechaza crear un tag directo a ciertos SHA que incluyen cambios de workflows cuando el token automático no tiene el permiso especial `workflows`;
- por esa limitación, el SHA del tag deja de ser la fuente autoritativa de identidad;
- cada Preview base publica `preview-build-identity.json` junto al APK;
- el manifiesto registra versión, build, SHA fuente, run de build y SHA-256 del APK;
- QA descarga APK + manifiesto y bloquea si versión/build/SHA/hash no coinciden con el gate;
- la recuperación se ejecuta dentro del workflow Shorebird original, que sí está autorizado ante `android-build-worker`;
- el workflow de recuperación provisional separado fue eliminado para evitar caminos duplicados.

### 3.6 QA después de un bloqueo temprano

Se detectó además que, cuando QA se bloqueaba antes de preparar artefactos, el paso final de salud intentaba escribir en `artifacts/backend/after.json` sin crear primero la carpeta.

Corrección:

- crear `artifacts/backend` incluso en rutas `if: always()`;
- commit CI: `b430a40baab8a9096cc316d6b60b0eed430629ae`;
- objetivo: conservar evidencia y evitar que un `FileNotFoundError` secundario oculte la causa principal del bloqueo.

---


### 3.7 QA #736: falso rojo geográfico y reparación del harness

**CONFIRMADO:** QA #736 no detectó crash Android ni fallo backend nuevo. El emulador terminó y el backend quedó `healthy`, pero el Evidence Gate bloqueó por `driver_request_seed_failed`.

Causa exacta:

- conductor QA: zona Trinidad, Bolivia;
- harness antiguo: Iquique, Chile;
- el trigger de cobertura rechazó el PATCH con “Tu ubicación actual no coincide con tu zona de conductor”.

Corrección vigente:

- el seed QA resuelve zona, centro, moneda y servicio desde el perfil/zona del conductor;
- el emulador usa las coordenadas emitidas por el mismo seed;
- `express-qa-provision` fija grupo `qa-core`, binding `preview` y `zone_id` Trinidad para las identidades sintéticas;
- la APK **1.6.0+153 no cambia** por esta reparación;
- Producción permanece intacta;
- se debe reejecutar QA sobre la misma identidad +153.


## 4. Regla oficial de artefactos Android

### Preview

**REGLA: Preview genera SOLO APK.**

- APK: sí
- AAB: no
- la APK que se entrega es la **base Shorebird**:
  `preview-shorebird-v<VERSION>-build<BUILD>/app-release.apk`
- el artefacto técnico `preview-android-...` no sustituye la base Shorebird para pruebas OTA.

### Producción

**REGLA: Producción genera APK + AAB.**

- APK: sí
- AAB: sí
- deben salir del mismo SHA aprobado en Preview.

No volver a generar AAB para Preview salvo instrucción explícita futura que reemplace esta regla y quede documentada.

---

## 5. Trazabilidad obligatoria de release

Identidad de una release:

1. `version_name`
2. `build_number`
3. `commit_sha`
4. artefacto realmente generado
5. tag/release
6. `app_release_gate`
7. workflow/run
8. SHA realmente auditado por QA

**REGLA:** los ocho elementos deben coincidir.

Cadena válida:

`commit -> Shorebird release/patch -> artefacto -> tag/release -> gate -> QA exacto -> aprobación -> Producción mismo SHA`

Nunca:

- certificar por el nombre visible del workflow;
- certificar un run verde sin artefacto;
- dejar que QA pruebe una Preview anterior;
- actualizar el gate antes de publicar correctamente;
- reconstruir Producción desde un `main` posterior “parecido”.

### Gate

Para una nueva base:

`Shorebird publish -> exact gate registration -> workflow success -> QA exact trigger SHA`

QA automático iniciado por `workflow_run` exige que:

`gate.preview_commit_sha == workflow_run.head_sha`

Si no coincide, QA debe bloquear.

---

## 6. Shorebird

### Patch permitido

Usar patch si:

- la base activa es la correcta;
- versión/build coinciden;
- el cambio es compatible con Dart patch;
- Shorebird acepta el patch sin diferencias nativas peligrosas.

### Nueva base obligatoria

Crear APK Preview nueva si:

- cambia código nativo;
- cambia dependencia nativa;
- Shorebird detecta native/DEX diffs no explicados;
- cambia una condición que el runtime base debe contener.

**REGLA:** una falla por native diffs no se “soluciona” ocultándola.

---

## 7. QA: qué significa realmente “probado”

Workflow principal:

`Express QA Auditor`

QA debe:

1. resolver Preview desde `app_release_gate`;
2. verificar versión/build;
3. verificar SHA;
4. hacer checkout del SHA auditado;
5. verificar el release Shorebird correspondiente;
6. ejecutar evidencia funcional;
7. clasificar el resultado.

Veredictos:

- `healthy`
- `confirmed_product_failure`
- `qa_inconclusive`
- `qa_infrastructure`
- `warning`

**REGLA:** rojo no significa automáticamente bug de producto.

Un error de identidad, gate, credencial de harness, emulador o Maestro es infraestructura/no concluyente hasta demostrar fallo funcional.

### QA manual de viajes

Existe un flujo de prueba controlado para crear solicitudes y confirmar ofertas en Preview.

**REGLA:** cualquier autoaceptación/confirmación automática usada por QA es solo para pruebas; no se debe convertir accidentalmente en lógica general de Producción.

---

## 8. Flujo funcional de viaje — reglas de producto

Esta sección describe el comportamiento que la app debe preservar. Cada cambio debe verificarse contra el código actual antes de declararlo implementado.

### 8.1 Pasajero

Flujo objetivo:

1. abrir Inicio map-first;
2. resolver ubicación;
3. seleccionar origen;
4. seleccionar destino;
5. elegir tipo de servicio;
6. ver tarifa sugerida;
7. solicitar viaje;
8. entrar a “Buscando conductor”;
9. recibir ofertas;
10. seleccionar/confirmar conductor según flujo configurado;
11. seguimiento de conductor en camino;
12. conductor marca “Ya llegué”;
13. pasajero ve espera;
14. pasajero puede indicar “Ya voy”;
15. inicio con PIN;
16. viaje en progreso;
17. finalización;
18. historial.

### 8.2 Conductor

Reglas solicitadas/activas a preservar:

- Conectar/Desconectar debe mostrar feedback de activación/desactivación.
- Solicitudes visibles deben respetar vehículo, zona, radio, entorno/canal y demás reglas operativas.
- Auto no recibe solicitudes Moto y viceversa.
- Oferta del conductor tiene ventana de **30 segundos**.
- Puede aceptar/rechazar y, cuando aplique, ofertar ajustes como +1/+2 en moneda local.
- Mientras espera confirmación del pasajero no debe recibir nuevas ofertas que interfieran.
- Si la oferta expira/rechaza, volver a estado disponible sin dejar estado colgado.
- Cuando el pasajero confirma:
  - el viaje pasa a conductor en camino;
  - no debe existir una pantalla redundante “Ir al pasajero” previa;
  - debe aparecer “Ya llegué”.
- Al marcar llegada, conductor y pasajero deben reflejar el mismo estado de espera.
- El conductor debe ver contador de espera cuando corresponda.
- “Ya voy” del pasajero debe notificarse al conductor.
- Inicio del viaje exige PIN.
- Finalizar viaje requiere confirmación visual antes de cerrar/cobrar.
- Cancelar debe cortar contadores, limpiar estado y volver al panel correcto.

### 8.3 Estados y transición

No alterar estados de backend solo para acomodar UI.

Cuando se detecte un estado inconsistente:

- verificar backend;
- verificar suscripciones/realtime;
- limpiar UI derivada;
- no inventar un estado paralelo local que pueda quedar desincronizado.

---

## 9. Mapa y rutas — reglas

### Pasajero y conductor

- El mapa debe centrar automáticamente los puntos relevantes.
- En ruta activa debe mostrar polilínea real cuando exista.
- El zoom debe encuadrar los dos puntos relevantes.
- El movimiento del conductor debe actualizar la ruta/posición sin reconstruir toda la pantalla.
- Evitar refrescos globales que cierren inputs o recarguen el mapa innecesariamente.
- Pin de selección de ubicación debe permanecer estable durante el gesto y resolver dirección al soltar/confirmar.
- Origen y destino deben mostrarse en oferta, seguimiento e historial.
- El botón “Mapa” del conductor puede actuar como atajo a navegación externa (por ejemplo Waze) cuando esa sea la decisión vigente, pero esto es diferente del botón **Llamar**.

### Vehículos cercanos

- Mostrar tipo de vehículo compatible con servicio seleccionado.
- Moto y auto no deben mezclarse si el filtro de servicio exige uno específico.
- Mostrar varios vehículos cercanos cuando existan, no un único marcador artificial.

---

## 10. Tarifa y demanda

**REGLA de producto solicitada:** la tarifa sugerida puede variar con demanda.

Principio esperado:

- demanda alta -> tarifa sugerida sube;
- demanda baja -> tarifa puede normalizarse/bajar dentro de límites;
- nunca romper mínimos/máximos configurados;
- toda fórmula debe ser administrable o documentada;
- antes de Producción, validar que el cálculo real coincida entre pasajero, conductor, backend y Admin.

**PENDIENTE DE VALIDAR:** cualquier IA futura debe revisar el código/RPC de pricing y Admin antes de afirmar que el algoritmo de demanda está completamente certificado.

---

## 11. Llamadas privadas pasajero ↔ conductor

Proveedor RTC:

**ZEGOCLOUD**

Reglas:

- solo audio 1 a 1;
- número telefónico real no se comparte entre las partes;
- ServerSecret nunca vive en cliente;
- la llamada se prepara en backend;
- solo participantes del viaje pueden llamar;
- depende de reglas de verificación telefónica configuradas;
- botón **Llamar** del viaje activo debe entrar a `ExpressPrivateVoiceCall`;
- no debe abrir `tel:`, Teléfono, Zoom ni otra app externa.

Validación mínima:

1. tocar **Llamar**;
2. aparece `zego-call prepare`;
3. se crea registro de llamada;
4. se envía invitación ZEGOCLOUD;
5. receptor puede aceptar;
6. Android no muestra selector externo.

Archivo de referencia:

`docs/PRIVATE_VOICE_CALLS.md`

---

## 12. Notificaciones

Regla de experiencia solicitada:

- app en primer plano: preferir aviso interno + sonido, evitando duplicar con push del sistema;
- app en segundo plano: push del sistema;
- oferta del conductor: alerta breve y visible durante la ventana de oferta;
- no mostrar notificaciones duplicadas por la misma transición;
- conservar `ic_stat_express` en Android;
- fallos de push deben registrarse para QA/observabilidad.

**PENDIENTE DE VALIDAR:** comprobar comportamiento real por estado de app en cada candidato antes de certificar.

---

## 13. UI/UX que no debe regresarse

Requisitos recurrentes del propietario:

- modo oscuro debe cubrir paneles, selectores, mapa/overlays y cambio Pasajero/Conductor;
- íconos de barra inferior deben ser visibles;
- Historial reemplaza el antiguo acceso de Servicios cuando esa navegación esté vigente;
- tarjeta “esperando solicitudes” del conductor debe ser estable, responsiva y sin huecos;
- tarjeta de oferta debe ser compacta;
- transiciones deben dar feedback y no parecer “pegadas”;
- evitar overlays que oculten botones;
- “Buscar conductor” debe respetar safe areas;
- las pantallas deben evitar espacios blancos excesivos;
- cambios de estado deben actualizar secciones necesarias, no reconstruir toda la app.

Toda modificación visual importante debe pasar QA visual/manual.

---

## 14. Seguridad y confianza

Funciones/requisitos de seguridad del producto:

- botón de pánico/SOS;
- compartir viaje;
- verificación de identidad/conductor;
- selfie/documento cuando corresponda;
- Didit como proveedor de verificación donde esté configurado;
- PIN obligatorio para iniciar viaje;
- controles de cuenta/bloqueo;
- “solo mujeres” como función administrable cuando esté habilitada por negocio/mercado.

**REGLA:** no exponer secretos, API keys privadas, service-role keys, ServerSecrets, contraseñas de firma ni keystores en Git.

---

## 15. OTP y verificación telefónica

Existen controles administrativos separados para pasajero y conductor.

Con switches OFF:

- no exigir OTP;
- no bloquear uso por teléfono no verificado.

Con switches ON:

- pasajero verifica antes de acciones restringidas configuradas;
- conductor verifica antes de conectarse/ofertar cuando aplique.

Router OTP y proveedores: ver `docs/PHONE_OTP_ROUTER.md`.

**REGLA:** no activar masivamente un proveedor o requisito OTP en Producción sin credenciales, pruebas y costo/entregabilidad validados.

WhatsApp OTP debe tratarse como integración separada si se incorpora; no asumir que está activo solo porque exista un número de WhatsApp configurado.

---

## 16. País, moneda y pago de viajes

Chile:

- prefijo: +56
- moneda: CLP
- mostrar CLP sin decimales

Bolivia:

- prefijo: +591
- moneda: BOB
- entero sin .00; fracción con dos decimales cuando exista

Regla vigente documentada en AGENTS:

- viaje ordinario: efectivo según configuración;
- Bolivia puede usar QR del conductor cuando corresponda;
- pasarelas administrativas/suscripciones no deben mezclarse automáticamente con cobro de viaje.

---

## 17. Adminexpress — responsabilidades

Admin vive separado de la app.

Controles requeridos/esperados incluyen:

- países/ciudades/zonas;
- zonas y cobertura;
- tarifas base;
- límites;
- demanda/surge si aplica;
- comisiones;
- categorías Auto/Moto;
- método de pago;
- tiempos de espera/cancelación;
- ofertas;
- duración de popups;
- switches de OTP;
- “solo mujeres”;
- permisos/feature flags;
- métricas;
- historial/cancelaciones;
- configuración de seguridad.

**REGLA:** no volver a incrustar el panel Admin dentro del repo/app Express.

---

## 18. Separación Preview / Producción

Runtime:

- `preview`
- `production`

**REGLA:** cuentas/datos QA no deben contaminar Producción.

Al reparar una prueba:

- no eliminar guards de aislamiento;
- no cambiar `channel` para “hacer que funcione”;
- corregir el harness o datos de prueba.

---

## 19. Documentación obligatoria

Regla permanente:

> **CODE CHANGED = DOCS MUST CHANGE**

Para cada cambio:

- actualizar `docs/CHANGELOG_ACTIVE.md`;
- actualizar este handoff si cambia estado, arquitectura, reglas, release o QA;
- actualizar documento específico del módulo;
- registrar versión/build/SHA si aplica;
- registrar qué se eliminó/reemplazó;
- registrar riesgos y pendientes.

Una tarea sin documentación aplicable está incompleta.

---

## 20. Prohibiciones importantes

No:

- cambiar package IDs;
- regenerar firma Android sin necesidad/autorización;
- mezclar Preview y Producción;
- saltarse el release gate;
- usar AAB en Preview;
- promover Producción desde un SHA distinto al Preview aprobado;
- usar workflow verde como única evidencia;
- forzar Shorebird native diffs para ocultar incompatibilidad;
- restaurar `tel:` para llamadas de viaje activo;
- exponer números reales de pasajero/conductor;
- volver a meter Adminexpress dentro de esta app;
- activar OTP sin proveedor/configuración válida;
- asumir que una solicitud de feature ya quedó implementada sin revisar código/QA.

---

## 21. Qué revisar antes de tocar código

Checklist mínimo:

- [ ] leer `AGENTS.md` y este handoff;
- [ ] revisar `pubspec.yaml`;
- [ ] revisar SHA de `main`;
- [ ] revisar últimos workflows;
- [ ] revisar release/tag vigente;
- [ ] revisar gate si el cambio toca Android;
- [ ] identificar Preview o Producción;
- [ ] identificar si el cambio es Dart-only o nativo;
- [ ] revisar documento específico del módulo;
- [ ] planear QA;
- [ ] documentar antes de cerrar.

---

## 22. Estado de continuidad inmediato

Al entregar este handoff actualizado:

1. +152 compiló, publicó APK y actualizó gate, pero **NO quedó certificada** porque el tag apuntó a un SHA documental distinto;
2. la causa raíz del tag quedó corregida en el workflow con `--target "$GITHUB_SHA"`;
3. se lanzó Preview **1.6.0+153** desde `b0093637d363ed3e19b38fc5ab206502bb79976e`;
4. +153 debe publicar **solo APK**;
5. después debe actualizar gate con el mismo SHA;
6. QA debe comprobar release/tag/gate sobre ese mismo SHA;
7. después se realiza prueba manual de llamada pasajero ↔ conductor;
8. Producción permanece sin tocar hasta aprobación explícita.

### Evidencia esperada para cerrar +153

- workflow Shorebird success;
- tag `preview-shorebird-v1.6.0-build153`;
- `app-release.apk` publicado;
- gate = 1.6.0+153;
- gate SHA = SHA publicado;
- QA = mismo SHA;
- llamada interna = ZEGOCLOUD;
- sin selector Teléfono/Zoom;
- documentación/changelog actualizados.

---

## 23. Mapa de referencias

- Inicio y arquitectura general: `docs/START_HERE_EXPRESS.md`
- Política documental: `docs/DOCUMENTATION_POLICY.md`
- Historial activo: `docs/CHANGELOG_ACTIVE.md`
- QA: `docs/QA_AUTOMATION.md`
- Llamadas privadas: `docs/PRIVATE_VOICE_CALLS.md`
- OTP: `docs/PHONE_OTP_ROUTER.md`
- Google Play: `docs/GOOGLE_PLAY_SUBMISSION.md`
- Delivery V2: `docs/EXPRESS_DELIVERY_V2_IMPLEMENTATION.md`
- Roadmap seguro: `docs/SAFE_IMPLEMENTATION_ROADMAP.md`
- Handoff trazabilidad anterior: `docs/AI_HANDOFF_2026-10-05_RELEASE_TRACEABILITY.md`
- Handoff histórico anterior: `docs/AI_HANDOFF_2026-10-04.md`

---

## 24. Regla de transferencia a otra IA

Si el propietario cambia de IA/agente en cualquier momento, el nuevo sistema debe poder continuar únicamente con el repositorio.

Por eso:

- una decisión importante que solo esté en chat se considera **no transferida**;
- debe quedar en este handoff, changelog o documento específico;
- los estados temporales deben actualizarse cuando cambien;
- no borrar handoffs históricos: marcarlos como históricos;
- el handoff maestro más reciente siempre debe estar primero en `AGENTS.md`.

**Objetivo final:** ninguna IA futura debe necesitar “adivinar” cómo funciona Express ni reconstruir decisiones críticas leyendo conversaciones antiguas.
