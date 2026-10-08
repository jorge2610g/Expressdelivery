> **ACTUALIZACIÓN AUTORITATIVA 2026-10-08:** para arquitectura única y ritmo de compilaciones, `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md` prevalece sobre el flujo Preview automático descrito en este documento histórico. QA Web se ejecuta con cada PR/main; Android QA se compila únicamente a petición; el gate de Producción aún exige manualmente Preview certificado hasta migración probada. No confundir desactivar automatización con gate migrado.

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
3. `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`
4. `docs/DOCUMENTATION_POLICY.md`
5. `docs/CHANGELOG_ACTIVE.md`
6. `docs/START_HERE_EXPRESS.md`
7. `docs/QA_AUTOMATION.md`
8. `docs/PRIVATE_VOICE_CALLS.md`
9. `docs/PHONE_OTP_ROUTER.md`
10. `docs/GOOGLE_PLAY_SUBMISSION.md`
11. documentación específica del módulo que se vaya a tocar

Los handoffs del 2026-10-04 y 2026-10-05 quedan como **historial técnico** y evidencia de decisiones anteriores.

---

## 1.1 Experimento controlado +165: Internal Testing con runtime por cuenta

**PENDIENTE DE VALIDAR / NO PRODUCCIÓN:**

- se conserva Preview como APK/laboratorio separado;
- Preview compilado sigue siendo estricto y no acepta cuentas Producción;
- el candidato Producción puede resolver una cuenta QA autorizada hacia `preview` después del login;
- una cuenta normal se resuelve a `production`;
- la autoridad es Supabase, no un flag manipulable por el cliente;
- Preview/Producción financieros siguen aislados por `runtime_channel`;
- finalidad: QA final sobre el AAB real de Producción en Google Play Internal Testing y promoción del mismo artefacto sin recompilar;
- si +165 falla, volver a las identidades congeladas Preview 164 / candidato Producción 132.

## 1.2 AdMob app-ads.txt · 2026-10-07

**CONFIRMADO EN REPOSITORIO / WEB:**

- dominio público/desarrollador: `https://expressviajes.online/`;
- archivo fuente: `web/app-ads.txt`;
- contenido autorizado: `google.com, pub-2194475962505382, DIRECT, f08c47fec0942fa0`;
- `deploy-web.yml` lo publica explícitamente como `/app-ads.txt` en la raíz del dominio;
- este cambio no habilita AdMob Producción por sí solo: los anuncios reales siguen requiriendo App ID + Ad Unit ID reales y el flag de Producción correspondiente.


## 1.3 Corrección QA/login por timeout PostgREST · 2026-10-07

**IMPLEMENTADO / PENDIENTE DE REVALIDAR:**

- QA run 37652043017 arrancó correctamente Preview y Producción pero falló en smokes autenticados mientras PostgREST registró `Warp server error: Thread killed by timeout manager`;
- Auth móvil reintenta una vez los RPC transitorios previos al login y la resolución de runtime;
- el harness repite una vez pasajero/conductor tras una pausa corta y conserva bloqueo si el segundo intento falla;
- es cambio Dart-only + QA; no requiere nueva base Android salvo que Shorebird rechace el patch;
- relanzar QA sobre Preview 1.6.1+169 después del patch/código de control actualizado.


## 1.9 Documentos de conductor por país · 2026-10-07

**BACKEND CORREGIDO:**

- Bolivia: Carné de identidad activo/obligatorio; Licencia de conducir inactiva.
- Chile: Cédula de identidad y Licencia de conducir activas/obligatorias.
- El estado incorrecto anterior tenía los cuatro requisitos inactivos y provocaba el chip `Inactivo` en AdminExpress.
- Preview usa shadow independiente `driver_document_requirements` en `admin_environment_config`.
- No requiere APK nuevo: `driver_onboarding_catalog` consume la configuración activa del backend.
- Migración aplicada/versionada: `20261007233500_driver_document_country_policy.sql`.

## 1.8 Admin Runtime Scope · 2026-10-07

**IMPLEMENTADO EN BACKEND / COORDINADO CON ADMINEXPRESS:**

- AdminExpress conserva una sola UI, pero Preview y Producción tienen autorización y data-plane explícitos;
- `admin_users` incorpora `allow_preview` / `allow_production`;
- `admin_access_context` devuelve entornos permitidos y default;
- RPC administrativas sensibles v2 requieren `p_channel` y validan el runtime del registro objetivo;
- una cuenta QA/Preview no puede mutarse desde el panel en Producción ni una cuenta Producción desde Prueba;
- auditoría v2 mantiene separación incluso para eventos legacy sin campo environment explícito;
- los monitores de zona continúan Producción-only;
- fuente backend: migraciones `20261007230500_admin_runtime_scope_isolation.sql` y `20261007232000_admin_runtime_scope_document_fix.sql`;
- frontend coordinado vive en `jorge2610g/Adminexpress`, no dentro del APK.

## 1.7 Express Motion System · 2026-10-07

**IMPLEMENTADO EN RAMA / PENDIENTE DE VALIDAR EN PREVIEW:**

- sistema de animación propio `express_motion.dart`, 100% Flutter nativo y sin paquete adicional;
- navegación global Mobile/Web: fade + desplazamiento horizontal sutil;
- login/registro: transiciones de modo, campos y estados de botón;
- onboarding conductor: progreso animado, cambio de paso y footer con estado visual;
- accesibilidad: `disableAnimations` del sistema operativo desactiva movimiento decorativo;
- regla: ninguna animación espera backend/GPS ni altera lógica de negocio; el movimiento acompaña el estado y nunca lo gobierna;
- siguiente expansión prevista después de validar esta base: solicitud de viaje, búsqueda de conductor, viaje activo, pagos/perfil y microinteracciones.

## 1.6 Moneda, documentos y estado operativo admin · 2026-10-07

**IMPLEMENTADO EN RAMA / BACKEND ADMIN YA APLICADO / PENDIENTE DE VALIDAR EN PREVIEW:**

- Iquique debe presentar CLP desde el contexto de zona cacheado/autoritativo; nunca usar BOB como moneda visual predeterminada mientras la zona termina de refrescar;
- `PassengerMapHome` recibe la zona resuelta por el landing y una lectura de catálogo sin coordenadas no puede borrar esa zona;
- onboarding conductor silencioso reutiliza caché y no abre permisos GPS automáticamente cada vez que se entra a la pantalla;
- `driver_onboarding_catalog` es la autoridad de requisitos; actualmente Iquique y Trinidad tienen 0 `driver_document_requirements.active=true`;
- `admin_update_driver_profile` conserva el estado vivo del conductor durante ediciones normales y evita el rebote offline/online que chocaba con el guard GPS;
- el estado online/busy solo puede originarse desde el runtime del conductor con ubicación válida; Admin mantiene capacidad de forzar offline.

## 1.5 GPS por niveles y primer arranque no bloqueante · 2026-10-07

**IMPLEMENTADO EN RAMA / PENDIENTE DE VALIDAR:**

- fuera de tracking, ubicación = caché local primero + fix moderado solo si hace falta;
- el splash nativo solicita permisos pero no espera indefinidamente un fix GPS fresco cuando el servicio está encendido;
- contexto de ciudad/moneda/servicios reutiliza caché reciente y evita RPC de zona si no hubo desplazamiento significativo;
- mapas muestran la última posición inmediatamente y refinan después con GPS preciso;
- durante viaje/delivery activo el stream de conductor usa alta frecuencia; estando solo online usa frecuencia menor;
- el dispositivo mantiene GPS activo para tracking, pero el backend recibe puntos deduplicados por distancia/rumbo con heartbeat para evitar que pasajero y conductor se separen visualmente;
- esta arquitectura busca menor batería/RPC fuera de tracking sin debilitar precisión en viaje.

## 1.4 Trazabilidad Producción endurecida · 2026-10-07

**REGLA AUTORITATIVA NUEVA:**

- Producción Android vuelve a la secuencia Google Play solicitada: **siguiente build 138**;
- baseline almacenado: 137; al promover 138, el siguiente pasa a 139 automáticamente;
- ningún Preview/candidato interno puede saltar el contador;
- candidato Producción = misma versión + mismo SHA que Preview vigente;
- CI compara el SHA candidato con `main` en rutas móviles sensibles antes de compilar;
- CI inspecciona el APK resultante y publica manifiesto de identidad/hashes;
- worker vuelve a validar gate/SHA/build al finalizar;
- candidatos 166 se consideran inválidos/superseded y no deben entregarse ni promoverse.


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

### 2.3 Entry point Android único desde +163

**REGLA AUTORITATIVA:** Preview y Producción usan el mismo entrypoint funcional:

- Preview Android: `lib/mobile_main.dart`
- Producción Android: `lib/mobile_main.dart`
- Web: `lib/web_preview.dart`

`lib/preview_main.dart` es solo un wrapper de compatibilidad y no puede volver a tener un bootstrap/main independiente en CI.

Configuración de compilación:

- Preview: `EXPRESS_PREVIEW_MODE=true`
- Producción: `EXPRESS_PREVIEW_MODE=false`

Package IDs:

- Producción: `com.express.usuario1`
- Preview: `com.express.usuario.preview`

La lógica funcional debe ser idéntica. Ver `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`.

### 2.4 Cuenta única

**REGLA de producto:**

- una persona tiene una sola identidad Express;
- inicia como Pasajero;
- “Conducir con Express” añade/completa el perfil de conductor usando el mismo `user_id`;
- `active_mode` selecciona experiencia Pasajero o Conductor;
- un conductor no debe necesitar otra cuenta/correo para cambiar de modo;
- el modo Conductor requiere perfil/vehículo/documentación y aprobación cuando corresponda.

---

## 2.5 Candidato Preview +155 en curso

**PENDIENTE DE VALIDAR / RELEASE:**

- versión fuente: `1.6.0+155`;
- objetivo: nueva base Preview, **APK solamente**;
- incluye UI de llamadas solo audio en español;
- pasajero queda bloqueado dentro del viaje activo hasta finalizar/cancelar;
- panel/tarjeta de viaje activo usa altura por contenido;
- ventana flotante Android de ofertas con tres llaves: AdminExpress + switch conductor + permiso `SYSTEM_ALERT_WINDOW`;
- Preview tiene `driver_floating_offer_enabled=true`;
- Producción conserva `driver_floating_offer_enabled=false`;
- migraciones aplicadas y versionadas: `20261006095823_driver_floating_offer_preview155.sql` y `20261006100145_harden_driver_floating_offer_admin_rpc.sql`;
- no promover a Producción hasta QA real de la +155.

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



### 3.8 Nueva base +154 por rechazo seguro del patch ZEGOCLOUD

**CONFIRMADO:** el intento de patch sobre +153 para desacoplar OTP y endurecer la inicialización de ZEGOCLOUD fue rechazado por Shorebird después de compilar porque detectó diferencias nativas/DEX.

Shorebird reportó cambios en ZIM/ZEGOCLOUD, `GeneratedPluginRegistrant`, Firebase Messaging, Kotlin/coroutines y Didit. La política vigente prohíbe ocultar este tipo de diferencia con `--allow-native-diffs`.

Decisión vigente:

- Preview candidata pasa a **1.6.0+154**;
- +154 se crea como **nueva base APK**, no como patch;
- conserva la corrección funcional del commit `97ab71391ec2b02f959f8126f46389f390866436`;
- OTP continúa disponible, pero no condiciona llamadas;
- autorización de llamada = viaje activo + participantes asignados + canal correcto;
- ZEGOCLOUD registra system calling UI antes de `runApp`, comparte `navigatorKey` y reutiliza una sola instancia del signaling plugin;
- Producción continúa sin cambios.


### 3.9 QA +154: cancelación por timeout del harness, no por fallo confirmado

QA #741 auditó correctamente Preview **1.6.0+154** sobre SHA `a1e8e7a3de0dbbf3fe7261648ab0d8b52ac684a0`.

Evidencia confirmada:

- identidad/gate +154 correctos;
- guard de llamadas privadas pasó;
- build x86_64 QA pasó;
- smoke Android externo pasó;
- backend al finalizar: `healthy`, 0 fallos nuevos confirmados;
- el job fue cancelado al alcanzar el límite global de 35 min mientras un flujo Maestro autenticado permanecía esperando;
- faltó `device-verdict.json`, por lo que Evidence Gate clasificó infraestructura QA y no producto.

Corrección:

- futuros jobs QA: 60 min globales;
- timeouts independientes Maestro: 180 s smoke/visual, 240 s pasajero, conductor y solicitud viva;
- +154 **no se recompila** por este ajuste de QA;
- Producción permanece intacta.


### 3.10 +154: causa raíz de invitación ZEGO identificada

La prueba manual de las 05:38 CL confirmó que el flujo ya llegaba a ZEGOCLOUD, pero ZIM rechazaba el login del signaling:

- UIKit: `301001003`;
- ZIM: `50013`;
- mensaje: `userid length limit err`;
- estado de signaling observado: `disconnected`;
- `send()` devolvía `false`.

Causa raíz: `zegoUserId()` generaba `u_` + UUID sin guiones, total 34 caracteres. La corrección usa solo el UUID sin guiones (32 caracteres).

Impacto:

- cambio backend en `zego-call`;
- no requiere recompilar Preview +154 ni publicar patch;
- OTP continúa desacoplado de llamadas;
- autorización sigue limitada al viaje activo y sus dos participantes;
- números reales siguen ocultos;
- Producción no se promueve por este cambio.


### 3.11 PENDIENTE +155: interfaz de llamada de audio Express

El propietario reservó para Preview **1.6.0+155** el siguiente cambio visual de llamadas privadas:

- traducir al español toda la UI visible de ZEGOCLOUD;
- eliminar/ocultar el recuadro flotante del participante que parece una videollamada;
- mantener el flujo estrictamente de audio;
- diseño esperado: avatar/nombre del otro participante al centro, duración visible y controles **Micrófono · Altavoz · Colgar**;
- conservar privacidad de números, autorización por viaje activo y roles pasajero/conductor;
- OTP permanece disponible como función independiente y no debe volver a condicionar la llamada.

**Estado:** PENDIENTE DE IMPLEMENTAR. Otra IA no debe asumir que este pulido ya está en +154.


### 3.12 Preview +154: restaurada persistencia de sesión

**CONFIRMADO:** el motivo por el que Preview volvía a pedir credenciales al cerrar/reiniciar la app era deliberado en código: `lib/preview_main.dart` usaba `EmptyLocalStorage` y un PKCE storage en memoria.

Origen histórico: en +150 hubo un problema de arranque con `shared_preferences_android` y se desactivó temporalmente la persistencia de auth para mantener Preview bootable.

Decisión vigente:

- la base +154 ya es una base Android nueva;
- Preview vuelve a usar el almacenamiento persistente estándar de `supabase_flutter`, igual que Producción;
- no se cambia ninguna credencial ni política de autenticación;
- tras instalar/aplicar el cambio, puede hacer falta iniciar sesión una última vez porque las sesiones creadas con `EmptyLocalStorage` nunca se guardaron;
- después de ese login, cerrar o reiniciar la app debe conservar la sesión;
- cambio Dart-only, candidato a patch Shorebird sobre +154;
- Producción permanece intacta.


### 3.13 PENDIENTE +155: ventana flotante de ofertas sobre otras apps

**DECISIÓN DE PRODUCTO:** Express debe ofrecer al conductor, de forma voluntaria, una ventana flotante para nuevas solicitudes de viaje cuando esté **en línea** y la app esté en segundo plano o el conductor esté usando otra aplicación.

Reglas obligatorias:

- Android utilizará el permiso especial **Mostrar sobre otras aplicaciones** (`SYSTEM_ALERT_WINDOW`) únicamente para esta función.
- El permiso **NO puede venir activado por defecto** ni concederse silenciosamente. El conductor debe activarlo expresamente desde Ajustes de Android después de una explicación clara dentro de Express.
- Debe existir un switch visible en la app del conductor: **Ventana flotante de ofertas**.
- Debe existir además un switch global en **Adminexpress**: **Permitir ventanas flotantes de ofertas**.
- El switch administrativo solo habilita/disponibiliza la función; **nunca puede sustituir ni forzar el permiso del sistema operativo**.
- La ventana solo aparece cuando:
  1. el conductor está autenticado, aprobado y **online**;
  2. existe una solicitud real y vigente compatible con su zona/vehículo/canal;
  3. la app está en segundo plano o el conductor está fuera de Express;
  4. Admin habilitó la función;
  5. el conductor habilitó la función;
  6. Android concedió el permiso de superposición.
- La ventana debe identificarse claramente como **Express** y mostrar, como mínimo: tiempo restante, tarifa, origen, destino y acciones **Aceptar / Rechazar**.
- **Rechazar** cierra la ventana inmediatamente y deja al conductor en la app/pantalla donde estaba.
- Si la oferta **expira**, la ventana se cierra sola.
- **Aceptar** abre Express y entra directamente al flujo real de esa solicitud/viaje; no debe crear estados paralelos locales.
- Si el permiso está apagado, el switch individual está apagado o Admin deshabilita la función, Express conserva el comportamiento alternativo normal sin forzar overlays.
- No utilizar `USE_FULL_SCREEN_INTENT` para disfrazar ofertas como llamadas. Las llamadas privadas pasajero↔conductor siguen siendo un flujo separado y pueden usar la experiencia de llamada entrante.
- No mostrar publicidad, promociones ni mensajes genéricos mediante esta superposición.
- La ventana debe desaparecer si el conductor pasa a offline, la solicitud deja de ser válida, el viaje se asigna a otro conductor, se cancela o cambia de canal/entorno.

**IMPLEMENTACIÓN:** pendiente. Como requiere permiso/servicio Android y cambios nativos, debe tratarse como **nueva base Preview +155** (o la siguiente base nativa si +155 se divide), no como patch Shorebird puramente Dart.

**QA obligatorio:** primer plano, segundo plano, launcher, otra app abierta, permiso concedido/denegado/revocado, switch conductor ON/OFF, switch Admin ON/OFF, rechazo, expiración, aceptación, solicitud asignada a otro conductor y cambio offline.


### 3.14 CONFIRMADO: disponibilidad del conductor bloqueada durante servicio activo

Prueba manual en Preview mostró que, durante **Conductor en camino**, el badge superior se veía como `Offline` porque el backend usa estado `busy`, pero el control todavía era interactivo. Al tocarlo podía cambiar `driver_profiles.online_status` a `online`, dejando al conductor potencialmente disponible para nuevas solicitudes durante un viaje.

Corrección vigente:

- si existe `activeTrip` o `activeDelivery`, el badge superior se fuerza visualmente a **Offline** y queda deshabilitado;
- `_toggleOnline()` rechaza defensivamente cualquier intento mientras el servicio siga activo;
- `ExpressService.setDriverOnline(true)` vuelve a comprobar viajes/deliveries activos y devuelve un error legible;
- migración `126_lock_driver_online_during_active_service.sql` refuerza la regla en PostgreSQL;
- el trigger `guard_driver_online_requires_driver_mode` rechaza pasar a `online` mientras exista:
  - viaje del conductor con estado distinto de `completed/cancelled`, o
  - delivery del conductor con estado distinto de `delivered/cancelled`;
- perfiles antiguos que hayan quedado `online` con servicio activo se normalizan a `busy`;
- `busy` continúa siendo el estado backend interno durante un servicio; la UI lo representa como **Offline/no disponible** porque el conductor no debe recibir nuevas solicitudes;
- el seguimiento GPS continúa por la existencia del servicio activo, independientemente de que no esté disponible para despacho;
- cuando el servicio termina/cancela correctamente, la disponibilidad puede volver a activarse según el flujo normal.

**Backend:** migración aplicada al proyecto oficial `zgpijrznvaskgcmauwxx`.

**Release:** cambio móvil Dart-only, candidato a patch Shorebird sobre +154. No requiere base nativa nueva por sí solo. Producción Android sigue sin promoverse.

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
- OTP/verificación telefónica permanece como función separada de cuenta y **no condiciona** iniciar ni recibir llamadas privadas;
- botón **Llamar** del viaje activo debe entrar a `ExpressPrivateVoiceCall`;
- no debe abrir `tel:`, Teléfono, Zoom ni otra app externa.

Validación mínima:

1. tocar **Llamar**;
2. aparece `zego-call prepare`;
3. se crea registro de llamada;
4. se envía invitación ZEGOCLOUD;
5. receptor puede aceptar;
6. Android no muestra selector externo.

Regla de integración ZEGOCLOUD:

- registrar `useSystemCallingUI` antes de `runApp`;
- usar la misma instancia de `navigatorKey` en CallKit y `MaterialApp`;
- inicializar signaling al iniciar/autorecuperar sesión;
- un fallo de `send()` debe dejar evidencia de estado de signaling y error ZEGO.

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

### Arquitectura Android vigente

**+163 reemplaza como modelo operativo a los candidatos anteriores.**

- Preview y Producción ya no tienen dos startups funcionales.
- `lib/mobile_main.dart` es el único entrypoint móvil oficial.
- `lib/preview_main.dart` queda como wrapper sin lógica propia.
- Shorebird, QA Preview, QA Production-mode, APK Producción y AAB Producción deben apuntar a `lib/mobile_main.dart`.
- Preview activa `EXPRESS_PREVIEW_MODE=true`.
- Producción activa `EXPRESS_PREVIEW_MODE=false`.
- Producción solo puede salir del mismo SHA certificado por QA.
- el smoke de Producción comprueba diferencias inevitables de empaquetado/configuración; no representa una segunda aplicación funcional.

### Candidato vigente

- versión: **1.6.0+163**;
- SHA candidato: `a3006e4d703e8ac12c87ccf74abc0fb068fd2999`;
- Shorebird inicial: run **#387**;
- +162 no debe promoverse;
- commits posteriores exclusivos de documentación no sustituyen el SHA candidato;
- Producción permanece bloqueada hasta publicación Shorebird + QA exacto + certificado gate + aprobación.

### Regla para otra IA

No arreglar Preview y Producción por separado. Si una función compartida falla, se corrige una vez en la base Express. Si solo Producción falla, investigar primero configuración/package/Firebase/manifest/firma/permisos, preservando el mismo código funcional.

Documento autoritativo específico:

`docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`

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


---

### ADDENDUM +155 — Ventana flotante de ofertas para conductor (2026-10-06)

**PENDIENTE DE IMPLEMENTAR.**

El propietario definió para el flujo del conductor una función opcional de **ventana flotante de ofertas** cuando Express esté en segundo plano.

Contrato funcional:
- conductor online/disponible;
- app en segundo plano;
- llega una oferta real vigente;
- si Admin habilitó la feature, el conductor activó su ajuste local y Android concedió **Mostrar sobre otras aplicaciones**, aparece la tarjeta Express sobre la app actual;
- **Rechazar** o expirar cierra la tarjeta sin abrir Express;
- **Aceptar** valida la oferta en backend, cierra el overlay y abre Express directamente en el flujo del viaje;
- no debe duplicarse con el popup foreground;
- no usar ofertas disfrazadas como llamadas/full-screen intent;
- el administrador no puede conceder el permiso Android por el conductor.

Control Admin requerido:
- switch: **Permitir ventanas flotantes de ofertas**;
- separado por Preview/Producción;
- clave sugerida: `driver_floating_offer_enabled`;
- OFF global impide overlays aunque el dispositivo conserve su permiso.

Control conductor requerido:
- ajuste visible: **Ventana flotante de ofertas**;
- consentimiento voluntario;
- permiso Android `SYSTEM_ALERT_WINDOW` solicitado mediante la pantalla oficial del sistema;
- permiso y preferencia son por dispositivo.

Documento autoritativo específico:
- `docs/FLOATING_DRIVER_OFFERS.md`

Coordinación Admin:
- `jorge2610g/Adminexpress/docs/FLOATING_DRIVER_OFFERS_ADMIN.md`

**No asumir que ya existe en +154.** La documentación registra el requisito; código, backend, QA y release siguen pendientes.

---

## 25. Hardening +161 tras fallo de arranque Producción

El test físico de Producción +159 reprodujo el mismo bloqueo de +158 después del splash. La revisión de punta a punta determinó que el problema no podía tratarse solo como un bug aislado: el proceso de promoción tenía huecos que permitían declarar una Preview lista sin ejercitar el entrypoint de Producción.

Estado autoritativo nuevo:

- +159: conocida como defectuosa en dispositivo; aprobación del gate invalidada.
- +160: APK genérico `preview-android`; diagnóstico únicamente, nunca promovible.
- siguiente candidato: **1.6.0+161**.
- bootstrap auth compartido: `lib/core/express_supabase_bootstrap.dart`.
- Preview y Producción deben ejecutar el mismo contrato de inicio.
- QA debe arrancar `com.express.usuario1` y `com.express.usuario.preview`.
- QA completo debe validar solicitud, oferta, selección, estados, PIN, finalización y rating pasajero↔conductor.
- un Preview solo es aprobable después de que `app_release_gate.qa_preview_build_id / qa_commit_sha / qa_passed_at` coincidan con el Preview vigente.
- Producción solo puede compilar el SHA/build/version exactos de ese Preview QA y posteriormente aprobado.
- `android-build-worker` acción `qa_certify` es la única ruta del workflow para registrar el certificado automático.
- el trigger de release gate acepta como Preview autoritativa únicamente URL `preview-shorebird-...`.

No crear manualmente Producción para saltar QA. Si QA falla, reparar evidencia/producto y volver a generar/certificar Preview.

### Candidato final de esta auditoría: +162

- +161 no debe promoverse: se detectó tag drift entre GitHub Release y SHA auditado.
- la causa quedó corregida con `--target "$GITHUB_SHA"` y recovery que recrea el tag sobre `RECOVERY_TARGET_SHA`.
- versión siguiente: **1.6.0+162**.
- no tocar Producción hasta que +162 publique Preview Shorebird, QA certifique el mismo build/SHA y el gate permita aprobación.


---

## 26. Arquitectura Preview → Producción unificada (+163)

**Esta sección prevalece sobre cualquier descripción histórica de +155…+162 que sugiera dos entrypoints Android funcionales.**

### Antes

Preview ejecutaba su propio `main()` en `lib/preview_main.dart` y Producción ejecutaba `lib/mobile_main.dart`. Aunque compartían gran parte de la UI, el bootstrap podía divergir. Esto produjo falsa confianza: Preview podía pasar y Producción fallar al iniciar.

### Ahora

- único startup real: `lib/mobile_main.dart`;
- función compartida: `runExpressMobile(previewMode, packageName)`;
- Preview y Producción se diferencian mediante configuración explícita;
- todos los builders oficiales compilan `lib/mobile_main.dart`;
- QA certifica el SHA exacto;
- Producción hace checkout de ese SHA y no del HEAD más reciente;
- el release gate impide producir un SHA distinto.

### Diferencias permitidas

Package, Firebase, canal, nombre, firma, overlay QA, update tooling y formato de artefacto.

### Diferencias prohibidas

Auth/bootstrap, viajes, ofertas, PIN, cancelación, mapas, llamadas, ratings, pricing, historial y cualquier otra lógica funcional.

### Regla de fallo

Si Preview funciona y Producción falla, no crear un “fix de Producción” separado. Revisar las diferencias de empaquetado/configuración y corregir la base compartida o el builder.

Referencia completa:

`docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`

---

## 27. Contadores independientes y Producción precompilada

**REGLA AUTORITATIVA — reemplaza cualquier texto histórico que exija mismo build number Preview/Producción.**

Preview y Producción comparten:

- código funcional;
- `lib/mobile_main.dart`;
- `version_name`;
- commit SHA.

Preview y Producción **NO comparten build number**.

Estado informado por el propietario:

- Preview vigente: **1.6.0+163**;
- Play Store Producción: **build/versionCode 131**;
- siguiente Producción candidata: **132**.

Flujo:

`SHA A -> Preview 163 + APK Producción candidato 132 + AAB Producción candidato 132`

Los tres se generan antes de la aprobación.

- Preview sigue incrementando 163, 164, 165... según pruebas.
- Producción sigue 132, 133, 134... según releases reales.
- si Preview falla y Producción 132 nunca fue subida a Play, 132 puede reconstruirse desde la siguiente Preview corregida;
- si Preview pasa QA y es aprobada, el candidato 132 se promueve sin recompilar;
- APK y AAB Producción deben conservar los mismos hashes/bytes del candidato.

Backend:

- `build_jobs.artifact_type='candidate-apk+aab'`;
- `app_release_gate.next_production_build_number`;
- `app_release_gate.production_candidate_*`;
- `admin_promote_production_candidate(uuid)`;
- migración `127_independent_preview_production_build_numbers.sql`.

Si Play Console muestra un versionCode superior ya consumido en otro track/draft, se ajusta solo el contador Producción; no se cambia Preview ni el SHA funcional.

Referencia: `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`.