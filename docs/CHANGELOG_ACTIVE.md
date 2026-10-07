## 2026-10-07 · Backend Admin Runtime Scope · aislamiento Preview/Producción

- Supabase agrega permisos por entorno en `admin_users`: `allow_preview` y `allow_production`;
- `admin_access_context` expone entornos permitidos y entorno por defecto;
- nuevas guards: `admin_environment_allowed`, `admin_assert_environment`, `admin_user_runtime_environment` y `admin_assert_target_environment`;
- fichas y mutaciones sensibles de Admin reciben `p_channel` mediante RPC v2 y rechazan registros cuyo runtime pertenece al entorno contrario;
- se incluyen wrappers scoped para detalle/edición de usuario y conductor, documentos, detalle de viaje, aprobación, estado de cuenta y resolución SOS;
- `admin_audit_list_v2` clasifica eventos por entorno y corrige acciones legacy usando el runtime de la cuenta objetivo;
- AdminExpress puede usar el mismo correo para ambos entornos; la autorización queda separada en backend;
- migraciones: `20261007230500_admin_runtime_scope_isolation.sql` y corrección de retorno `20261007232000_admin_runtime_scope_document_fix.sql`;
- cambio backend/Admin únicamente; no modifica APK, package IDs ni contador Producción.

---

## 2026-10-07 · Express Motion System · animaciones Flutter nativas

- se crea `lib/express_motion.dart` como lenguaje central de movimiento de Express, sin dependencias externas nuevas;
- tiempos compartidos: 90/160/240/360 ms, curvas suaves y transición global fade + slide para navegación;
- el sistema respeta `MediaQuery.disableAnimations`: si Android/iOS/Web solicita reducir movimiento, las animaciones se colapsan;
- login/registro ahora anima cambio de encabezado, aparición de campos, estado del botón y cambio Login ↔ Crear cuenta;
- registro de conductor agrega progreso animado y transición entre pasos sin tocar validaciones, backend, GPS ni documentos;
- las rutas de Mobile y Web comparten la transición Express para que nuevas pantallas hereden una navegación visual consistente;
- no se agregó Lottie/Rive/flutter_animate: primera fase queda 100% Flutter nativo para minimizar peso y riesgo;
- cambio Dart-only/UI; no modifica package IDs, Supabase, build number ni contratos de Producción.

---

## 2026-10-07 · Moneda por zona inmediata + onboarding sin GPS repetitivo + edición admin segura

- se corrige la regresión donde Iquique podía mostrar temporalmente `Bs` aunque la tarifa ya estuviera calculada en CLP: el Home conserva/pasa la última zona autoritativa y resuelve zona con la ubicación cacheada antes de usar un fallback de moneda;
- una carga global de catálogo sin coordenadas ya no borra `activeZone`;
- el onboarding de conductor deja de pedir un fix GPS nuevo en cada apertura: en carga silenciosa usa ubicación local/cacheada y solo solicita permiso por una acción explícita del usuario;
- el backend `driver_onboarding_catalog` sigue siendo autoritativo para documentos; al 2026-10-07 Iquique (CLP) y Trinidad (BOB) tienen 0 requisitos documentales activos, por lo que la UI vigente debe omitir el paso de documentos;
- se aplica `admin_driver_status_preserve_gps_authority`: guardar datos de un conductor desde AdminExpress ya no hace un rebote `offline -> online` que disparaba falsamente `Activa el GPS antes de conectarte`;
- Admin puede forzar offline, pero no fabricar un estado online/busy para un conductor sin el GPS vivo de su dispositivo;
- no cambia package ID ni contador Google Play; validar primero en Preview antes de promover un nuevo candidato Producción.

---

## 2026-10-07 · GPS por niveles: caché suave fuera de tracking + tracking preciso

- el primer arranque ya no espera un fix GPS fresco para abandonar el splash: con permiso concedido y servicio de ubicación activo, Express entra y refina la posición en segundo plano;
- flujos que no necesitan mapa usan primero ubicación local/caché y un fix de consumo moderado solo cuando el caché está vencido;
- el contexto de pasajero reutiliza durante 15 minutos ciudad/moneda/servicios guardados y evita consultar zona al backend si el usuario se movió menos de 750 m;
- el mapa pinta primero la última ubicación local y luego la reemplaza por un fix GPS preciso sin bloquear la interfaz;
- pequeñas correcciones GPS (<200 m) no vuelven a consultar catálogo/zona solo para recentrar el mapa;
- tracking de conductor queda separado: alta frecuencia durante viaje/delivery activo y frecuencia reducida cuando solo está online esperando;
- el GPS local sigue recibiendo todos los puntos de tracking; las escrituras al backend se envían solo ante movimiento/giro relevante o heartbeat de seguridad (máximo ~12 s en viaje, ~30 s online);
- cambio Dart-only; no altera package IDs ni la secuencia de Producción 138→139→140.

---

## 2026-10-07 · Gate automático de trazabilidad Producción + contador 138→139→140

- se detecta deriva de identidad: se habían generado candidatos Producción build 166 aunque la secuencia solicitada para Google Play debe continuar en 138;
- baseline Producción se fija en 137 y siguiente candidato en **138**;
- candidatos 166 quedan invalidados para promoción;
- `next_production_build_number` pasa a ser derivado de `production_store_build_number + 1`;
- Preview/builds internos no pueden modificar el contador Google Play;
- `android-build-worker` valida candidato contra Preview vigente al reclamarlo y de nuevo al finalizarlo;
- CI bloquea Producción si `main` contiene cambios móviles posteriores al SHA candidato;
- CI valida contrato funcional mínimo: correo+teléfono+versión visible en Perfil, Mapbox, Ads Pasajero y entrypoint móvil compartido;
- el APK compilado se inspecciona para verificar package/versionName/versionCode;
- APK/AAB incluyen manifiesto de identidad con SHA fuente/tree y hashes SHA-256;
- tags de GitHub Release apuntan explícitamente al SHA realmente compilado;
- después de promover 138, el contador avanza automáticamente a 139; luego 140, etc.

---

## 2026-10-07 · Login/QA resiliente a timeouts transitorios de PostgREST

- QA 37652043017 dejó evidencia de arranque sano en Preview/Producción, pero los smokes autenticados coincidieron con `Warp server error: Thread killed by timeout manager` en PostgREST;
- `auth_entry.dart` reintenta una vez, con timeout corto, los RPC previos al login y la resolución de runtime;
- limpiar el login guard después de autenticación pasa a ser best-effort para no degradar un login válido por un timeout de bookkeeping;
- el harness QA reintenta una vez los smokes autenticados de pasajero/conductor tras 5 s y amplía la espera final de 30 s a 60 s;
- cambio Dart + harness, sin cambios nativos ni de package; debe intentar Shorebird patch sobre Preview 1.6.1+169 antes de crear nueva base;
- un segundo fallo sigue bloqueando el gate y requiere diagnóstico; no se certifica por reintento omitido.

---

## 2026-10-07 · AdMob app-ads.txt publicado para Express

- dominio de desarrollador: `https://expressviajes.online/`;
- se agrega `web/app-ads.txt` con la declaración autorizada de Google/AdMob para publisher `pub-2194475962505382`;
- el workflow `deploy-web.yml` copia explícitamente el archivo a `build/web/app-ads.txt` para garantizar `https://expressviajes.online/app-ads.txt` en cada despliegue;
- cambio exclusivamente web/configuración: no modifica la lógica móvil, no requiere nueva APK/AAB y no activa anuncios de Producción por sí solo;
- después del despliegue, AdMob debe volver a rastrear/verificar el archivo desde su consola.

---

## 2026-10-06 · 1.6.0+165 — candidato de Internal Testing con entorno resuelto por cuenta

- cambio aditivo y reversible; Preview 164 y Producción candidato 132 quedan congelados como respaldo;
- el APK Preview sigue siendo estricto y conserva su comportamiento actual;
- un candidato Android de Producción puede resolver, después del login, una cuenta QA ya autorizada hacia `preview`;
- las cuentas normales permanecen en `production`;
- el cliente no puede autodeclararse QA: Supabase resuelve el entorno desde `account_runtime_bindings` / membresía QA activa;
- `ExpressRuntimeChannel` separa ahora modo compilado de entorno de sesión resuelto por servidor;
- login por correo y gate post-auth usan el mismo resolver;
- wallet, pagos, tarifas, moneda por zona y suscripciones siguen consumiendo el mismo `runtime_channel`, ahora resuelto por cuenta;
- objetivo de release: generar AAB real de Producción, probarlo en Google Play Internal Testing y promover ese mismo artefacto sin recompilar si QA pasa;
- no publicar a Producción hasta completar QA funcional sobre el AAB definitivo.

---

## 2026-10-06 · QA #784 — falso rojo por conflicto UiAutomation

- Producción startup smoke pasó y quedó viva con 0 fatales de Express.
- Backend terminó `healthy` sin fallos nuevos confirmados.
- El watchdog QA competía con Maestro por Android UiAutomation mediante `uiautomator dump`.
- Los dos fatales observados eran del launcher de UiAutomator del sistema, no del package Express.
- Se elimina la concurrencia, se endurece el conteo de crashes por package y se añade retry/clasificación de infraestructura para fallos del driver Maestro.
- Se reejecuta QA sobre Preview 164 sin recompilar aplicación.

---

## 2026-10-06 · QA 782 — fallo de infraestructura por guard de tag obsoleto

- QA #782 no ejecutó emulador ni pruebas funcionales; se bloqueó en `Resolve audited Preview identity`;
- Preview 164 estaba correctamente registrada con SHA autoritativo `e825d908e0c103a6ca33db1fc8004ecfca60f6bb`;
- el tag visual de GitHub apuntaba al commit de recuperación/control-plane `6a8e212...`;
- el auditor todavía exigía erróneamente `tag SHA == preview_base_sha`;
- regla corregida: identidad autoritativa = `preview-build-identity.json` + `app_release_gate` + SHA-256 real del APK;
- el tag GitHub queda como referencia navegacional y ya no puede bloquear QA por sí solo;
- se inicializan carpetas de evidencia al inicio para evitar el error secundario `backend_snapshot_unreadable:FileNotFoundError` cuando QA termina antes del emulador;
- se relanza QA reutilizando exactamente Preview 164; no se recompila la aplicación.

---

## 2026-10-06 · Preview 164 — recuperación del módulo Auth Android

- Producción 132 confirmó arranque correcto, pero registro, recuperación y Google fallaban antes de llegar a Supabase;
- causa eliminada del camino crítico: `auth_entry.dart` construía el callback Android mediante `PackageInfo.fromPlatform()`, haciendo Auth dependiente de un plugin nativo antes de iniciar OAuth/signup/recovery;
- callback ahora se deriva exclusivamente de `EXPRESS_FIREBASE_PACKAGE_NAME`, la misma identidad explícita que CI usa para Preview/Producción;
- callbacks esperados: Preview `com.express.usuario.preview://login-callback/`, Producción `com.express.usuario1://login-callback/`;
- se agrega `test/auth_redirect_test.dart`;
- CI Producción queda fijado a Flutter 3.47.5, igual que Shorebird Preview, evitando toolchains 3.47.5/3.47.6 diferentes;
- CI analiza `auth_entry.dart` y ejecuta el test del callback antes del build caro;
- Preview avanza a 164; Producción candidata conserva versionCode 132 mientras 132 no haya sido publicada en Play;
- el login email/password sí alcanzó Supabase en Producción y un login válido fue registrado; los intentos con contraseña incorrecta también llegan al guard y Auth correctamente.

---

## 2026-10-06 · Trazabilidad candidata Producción 132 verificada

- Preview 163 y Producción candidata 132 fueron compiladas desde el mismo SHA funcional `a3006e4d703e8ac12c87ccf74abc0fb068fd2999`;
- ambos usan `lib/mobile_main.dart`; Preview compila con `EXPRESS_PREVIEW_MODE=true` y Producción con `false`;
- Producción usa package `com.express.usuario1`, build/versionCode 132, mientras Preview conserva build 163;
- APK Producción candidato SHA-256: `b455b702656ff62685a5ec57d1a67fedfc199981023bc62b6fff7196f2b34239`;
- AAB Producción candidato SHA-256: `a5ffde21978236df7f2854df8805d1e0b9b8cbe7b12a6ceec439ba04f314235a`;
- se detectó una anomalía solo de metadatos: el tag GitHub del candidato 132 se creó apuntando a `main` aunque el job hizo checkout y compiló el SHA `a3006e4d...`;
- el builder queda endurecido para que futuros tags de candidato/Producción usen `--target` con el `source_sha` auditado;
- esta anomalía de tag no cambia los bytes ya generados, pero se documenta porque la trazabilidad visual del release debe coincidir con el SHA real de compilación.

---
## 2026-10-06 · Build counters separados + Producción 132 precompilada

- se corrige la regla anterior que obligaba a Preview y Producción a compartir build number;
- Preview conserva contador independiente de pruebas: 163, 164, 165...;
- Producción conserva contador independiente para Google Play: baseline informado 131, siguiente candidato 132;
- identidad Preview→Producción = mismo SHA + mismo código funcional + mismo `version_name`, no mismo build number;
- APK y AAB de Producción sí comparten entre sí el mismo build number;
- nuevo tipo `candidate-apk+aab`: Producción se compila firmada antes de terminar la prueba Preview;
- si Preview pasa QA/aprobación, el candidato se promueve sin recompilar;
- si Preview falla y el versionCode Producción todavía no fue subido a Play, ese número puede reutilizarse;
- nuevo gate: `next_production_build_number` y `production_candidate_*`;
- nueva RPC: `admin_promote_production_candidate(uuid)`;
- migración aplicada: `127_independent_preview_production_build_numbers.sql`;
- candidato actual: Preview 163 / Producción candidato 132 / SHA `a3006e4d703e8ac12c87ccf74abc0fb068fd2999`.

---
## 2026-10-06 · 1.6.0+163 — Preview y Producción unificados sobre un solo entrypoint

- se elimina la arquitectura efectiva de dos startups Android que permitía que Preview funcionara mientras Producción fallaba;
- `lib/mobile_main.dart` pasa a ser el **único entrypoint funcional oficial** para Preview y Producción;
- `lib/preview_main.dart` queda como wrapper mínimo de compatibilidad, sin inicialización propia;
- Preview compila `lib/mobile_main.dart` con `EXPRESS_PREVIEW_MODE=true`;
- Producción compila el mismo archivo con `EXPRESS_PREVIEW_MODE=false`;
- Shorebird, QA Preview, smoke Production-mode y builder APK/AAB quedan alineados al mismo entrypoint;
- diferencias permitidas se limitan a package, Firebase/configuración, runtime channel, herramientas QA, firma y formato del artefacto;
- bootstrap Supabase/auth, viajes, ofertas, PIN, cancelación, mapas, llamadas, ratings y demás lógica funcional no pueden tener variantes separadas;
- Producción solo puede compilar el mismo SHA/version/build certificado por QA;
- los commits solo documentales posteriores a un candidato no cambian el SHA de aplicación que el gate debe promover;
- candidato inicial de la nueva arquitectura: `1.6.0+163`, SHA `a3006e4d703e8ac12c87ccf74abc0fb068fd2999`, Shorebird run #387;
- +162 pertenece al circuito anterior y no debe promoverse;
- documento autoritativo nuevo: `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`.

---

## 2026-10-06 · Preview 1.6.0+156 — base segura posterior a +155

- nueva base Preview creada porque Shorebird bloqueó el patch de +155 al detectar diferencias nativas durante la reconstrucción;
- no se fuerza `--allow-native-diffs`: se evita mezclar Dart nuevo con librerías Android distintas a la base;
- +156 conserva el comportamiento funcional de +155 y añade únicamente el feedback visual inmediato de llamadas privadas: **Conectando llamada…**, animación, bloqueo de doble toque y limpieza automática en éxito/error;
- la corrección de ofertas flotantes permanece en backend Preview: `ride_request` se entrega como FCM data-only de prioridad alta para permitir que el handler de segundo plano abra el overlay;
- no se actualizan plugins, permisos, firma, Firebase ni configuración de Producción en este corte;
- Preview continúa siendo **APK solamente**; no se publica AAB;
- Producción permanece bloqueada hasta validar manualmente llamada, ventana flotante, sesión persistente, bloqueo Atrás y tarjeta activa.

## 2026-10-06 · QA +155 — auditor reparado sin ampliar permisos de usuarios

- el primer QA posterior a +155 quedó rojo por **infraestructura QA**, no por una regresión confirmada: el APK reconstruido por el harness falló en `shared_preferences` y el sembrador recibió 403 al leer `service_zones`;
- el backend del mismo run salió `healthy`, sin nueva evidencia confirmada de producto;
- el auditor ahora usa el **APK Preview publicado exacto** y resuelve zona/servicio con el RPC seguro `app_zone_context`, igual que la app;
- no se concedió lectura directa de `service_zones`/`zone_service_catalog` al rol `authenticated`;
- se debe volver a ejecutar el auditor antes de aprobar el release gate de +155.
## 2026-10-06 · Preview 1.6.0+155 — llamadas, viaje activo y ofertas flotantes

- **Llamadas privadas:** ZEGOCLOUD sigue siendo audio 1:1, pero la UI de llamada se fuerza a modo voz: cámara apagada, barra superior oculta, duración visible y barra inferior limitada a **Micrófono / Altavoz / Colgar**. Los textos de invitación, permisos y controles quedan en español.
- **Pasajero durante viaje activo:** desde `driver_assigned` hasta `in_progress/emergency` el viaje queda bloqueado como superficie principal. Se bloquean flecha/menú, navegación inferior, gesto y botón Atrás de Android. El bloqueo se libera al desaparecer el viaje activo por finalización o cancelación válida.
- **Tarjeta activa:** el viaje activo deja de depender de una altura fija del `DraggableScrollableSheet`; usa contenido intrínseco dentro de un límite de pantalla, por lo que elimina el espacio blanco sobrante y crece solo cuando hay más información.
- **Ventana flotante de ofertas:** se agrega una superficie Android opcional sobre otras apps mediante `flutter_overlay_window`. Solo funciona cuando coinciden tres condiciones: AdminExpress permite la función en el entorno, el conductor activa su switch y Android concede `SYSTEM_ALERT_WINDOW`.
- **Aceptar desde la ventana:** guarda el `ride_request_id`, abre Express y entrega la solicitud al flujo real de ofertas; Rechazar o expirar cierra la ventana.
- **Separación de entornos:** Preview queda habilitado para validar +155. Producción queda apagado por defecto. El admin nunca puede conceder el permiso Android por el conductor.
- **Backend:** migraciones `20261006095823_driver_floating_offer_preview155.sql` y `20261006100145_harden_driver_floating_offer_admin_rpc.sql`.
- **Build:** `pubspec.yaml` pasa a `1.6.0+155`. Preview debe generar **APK solamente**; no se publica AAB de Preview.
- **Pendiente de validación manual:** confirmar persistencia de sesión cerrando/reabriendo Express, permiso Android real del overlay y flujo completo Aceptar/Rechazar/Expirar con dos dispositivos.

## 2026-10-06 · Conductor: disponibilidad bloqueada durante servicio activo

- video manual confirmó una regresión: con un viaje activo el badge superior aparecía **Offline**, pero todavía permitía tocarlo y pasar a **En línea**;
- durante cualquier viaje o delivery activo, el control de disponibilidad queda visualmente en **Offline** y deshabilitado;
- el conductor no puede volver a `online` hasta que el servicio termine o sea cancelado correctamente;
- la app agrega defensa adicional en `setDriverOnline(true)` y muestra un mensaje claro si un cliente viejo intenta conectarse con un servicio activo;
- backend endurecido con migración `126_lock_driver_online_during_active_service.sql`: el trigger rechaza `online_status='online'` mientras exista viaje/delivery activo;
- cualquier disponibilidad antigua `online` con servicio activo se normaliza a `busy`, conservando seguimiento del servicio pero evitando nuevas solicitudes;
- al terminar el servicio, la regla deja de bloquear la disponibilidad;
- cambio de UI/servicio es Dart-only y puede viajar como patch Shorebird sobre Preview +154; la migración backend ya está aplicada en el proyecto oficial;
- Producción Android no se promociona por este cambio.

---

## PENDIENTE · Preview 1.6.0+155 · Ventana flotante de ofertas del conductor

- decisión de producto documentada: el conductor podrá activar voluntariamente una **Ventana flotante de ofertas** para recibir solicitudes reales sobre otras apps mientras esté online y Express esté en segundo plano;
- Android usará `SYSTEM_ALERT_WINDOW` / **Mostrar sobre otras aplicaciones** únicamente con consentimiento explícito del conductor;
- habrá dos controles: switch global en Adminexpress + switch individual en la app del conductor;
- Admin nunca podrá conceder ni forzar el permiso Android;
- la ventana mostrará Express, tiempo restante, tarifa, origen/destino y **Aceptar / Rechazar**;
- rechazar o expirar cierra la ventana y deja al conductor donde estaba; aceptar abre Express directamente en la solicitud real;
- la superposición solo aplica a solicitudes vigentes y compatibles mientras el conductor esté online;
- no se usará `USE_FULL_SCREEN_INTENT` para simular llamadas con ofertas;
- llamadas privadas siguen siendo un flujo separado;
- requiere trabajo nativo Android y por tanto **nueva base Preview**, no patch Dart-only;
- estado: **pendiente de implementar y validar**; Producción no cambia.

---

## 2026-10-06 · Preview +154: sesión persistente al cerrar/reabrir la app

- se confirmó la causa de que Preview pidiera credenciales después de cerrar o reiniciar: `preview_main.dart` inicializaba Supabase con `EmptyLocalStorage` y PKCE en memoria;
- esa protección se había introducido históricamente para evitar el fallo de arranque de +150 relacionado con `shared_preferences_android`;
- la base +154 ya es una base Android nueva y Producción utiliza el almacenamiento persistente estándar de Supabase, por lo que Preview vuelve a usar el mismo mecanismo persistente;
- se elimina `EmptyLocalStorage` y el storage PKCE temporal de Preview;
- después de recibir este patch, la primera apertura puede requerir **un último inicio de sesión**, porque la sesión anterior nunca fue guardada; los siguientes cierres/reinicios deben conservar la sesión;
- cambio Dart-only: se intenta como patch Shorebird sobre +154;
- Producción no se modifica.

---

## PENDIENTE · Preview 1.6.0+155 · UI de llamadas Express

- reservado para +155 el pulido visual de llamadas privadas;
- todos los textos visibles de ZEGO deben mostrarse en español;
- retirar el recuadro flotante que parece una ventana de videollamada;
- mantener llamada solo audio;
- diseño objetivo: avatar/nombre central, duración y controles **Micrófono · Altavoz · Colgar**;
- conservar privacidad de números, roles del viaje y seguridad actual;
- OTP sigue separado de la llamada;
- estado: **pendiente de implementar y validar**, no realizado todavía.

---

## 2026-10-06 · Llamadas +154: corregido ZEGO 50013 por userID de 34 caracteres

- la prueba manual de las 05:38 CL mostró el fallo real de invitación;
- ZEGOCLOUD devolvió `301001003` / ZIM `50013 userid length limit err`;
- Express construía el ID ZEGO como `u_` + UUID sin guiones = 34 caracteres;
- se elimina el prefijo y se usa UUID sin guiones = 32 caracteres;
- signaling podrá autenticarse con un userID dentro del límite y `send()` deja de partir desde estado desconectado por ese error;
- no se cambia OTP, roles, seguridad de viaje ni privacidad de números;
- cambio solo backend `zego-call`: **no requiere nueva APK ni patch Shorebird**;
- Preview +154 sigue siendo el APK de prueba; Producción permanece intacta.

---

## 2026-10-06 · QA +154: evitar cancelaciones por flujo Maestro colgado

- Preview 1.6.0+154 fue publicada correctamente como nueva base APK;
- QA #741 resolvió versión/build/SHA correctos, pasó el smoke externo y reportó backend `healthy` con 0 fallos nuevos confirmados;
- el run no certificó porque el job tenía `timeout-minutes: 35` y un flujo Maestro autenticado quedó esperando hasta que GitHub canceló el job;
- se amplía el límite global futuro a 60 min y se añaden timeouts por flujo Maestro (180/240 s) para que un test atascado no impida generar `device-verdict.json`;
- este cambio es solo harness/documentación; **la APK +154 no cambia** y Producción sigue intacta.

---

## 2026-10-06 · Preview 1.6.0+154: nueva base obligatoria para la corrección ZEGOCLOUD

- el intento de publicar la corrección de llamadas como patch sobre `1.6.0+153` compiló, pero Shorebird bloqueó la publicación por diferencias nativas/DEX;
- diferencias reportadas: ZIM/ZEGOCLOUD, `GeneratedPluginRegistrant`, Firebase Messaging, Kotlin/coroutines y Didit;
- no se usa `--allow-native-diffs`; se mantiene la regla de no forzar parches cuando Shorebird detecta incompatibilidad nativa;
- Preview pasa a **1.6.0+154** para crear una base APK nueva y limpia con la corrección incorporada;
- la base incluye OTP desacoplado de llamadas, `useSystemCallingUI` antes de `runApp`, `navigatorKey` compartido, una sola instancia de signaling y telemetría ZEGO;
- Preview continúa generando **solo APK**;
- Producción permanece intacta hasta aprobación explícita y certificación del mismo SHA.

---

## 2026-10-06 · ZEGOCLOUD +153: OTP desacoplado y señalización corregida

- OTP se mantiene como función de cuenta, pero deja de ser requisito para iniciar o recibir llamadas privadas;
- `zego-call` v7 ya no evalúa `phone_verified_at` para `bootstrap` ni `prepare`;
- la seguridad de llamada sigue basada en viaje activo, participantes asignados, canal y cooldown;
- ZEGOCLOUD registra `useSystemCallingUI` antes de `runApp`;
- `MaterialApp` y CallKit reutilizan la misma instancia de `navigatorKey`;
- se reutiliza una sola instancia de `ZegoUIKitSignalingPlugin` para registro e inicialización;
- se agregan diagnósticos de init, estado de signaling, envío/recepción y errores de invitación;
- la corrección de app es Dart-only y se publica primero como patch Shorebird sobre Preview 1.6.0+153;
- Producción no se promueve automáticamente.

---

## 2026-10-06 · QA +153: zona dinámica y corrección del falso rojo geográfico

- QA #736 ejecutó la app y el emulador sin crash; backend final healthy y 0 fallos nuevos confirmados de producto.
- El Evidence Gate quedó rojo por `driver_request_seed_failed`: el harness fijaba Iquique (`-20.22843,-70.13847`) mientras el conductor QA pertenece a Trinidad.
- Se eliminan del flujo sintético las coordenadas, moneda y servicio hardcodeados de Iquique.
- `qa_driver_request_flow.py` ahora resuelve `zone_id`, centro, moneda y servicio habilitado desde el perfil/zona reales del conductor QA.
- El emulador toma GPS desde `driver-request-seed.json`, exactamente igual al viaje sintético.
- `express-qa-provision` fija de forma determinista las identidades QA al grupo `qa-core`, entorno Preview y zona Trinidad activa.
- Este cambio es de harness/backend QA; **no cambia la APK +153 ni Producción**.
- La misma Preview +153 debe reauditarse después del despliegue del aprovisionador QA.

---

## 2026-10-06 · QA usa ubicación real del conductor provisionado

- se corrigió `.github/scripts/qa_driver_request_flow.py`, que todavía forzaba coordenadas de Iquique durante el smoke del conductor;
- el auditor ahora lee `latitude/longitude/city/zone_id` del conductor QA provisionado y no cambia de ciudad artificialmente;
- la solicitud sintética usa `motorcycle`, compatible con el vehículo QA y con el catálogo activo de Trinidad;
- la moneda deja de estar hard-coded en CLP y se toma de `dynamic_pricing_quote`;
- el test de tarifa mínima respeta precisión por moneda (CLP entero, otras monedas con centavos);
- el fallo anterior fue del harness: el backend rechazó correctamente mover al conductor de Trinidad a una zona fuera de cobertura;
- Producción no fue modificada.

---

## 2026-10-06 · Preview +153 recuperada, identidad por manifiesto y QA endurecido

- Shorebird +153 compiló y publicó internamente correctamente; APK generado desde SHA fuente `b0093637d363ed3e19b38fc5ab206502bb79976e`;
- el primer intento de Release falló con HTTP 403 al usar `--target "$GITHUB_SHA"`; GitHub rechazó crear una ref directa al SHA porque la historia incluye cambios de workflows y el token automático no tiene permiso especial `workflows`;
- se descartó usar el SHA del tag como identidad autoritativa;
- +153 se recuperó sin recompilar usando el artifact original del run `37413043227`;
- Release público: `preview-shorebird-v1.6.0-build153`;
- el Release incluye `app-release.apk` y `preview-build-identity.json`;
- el manifiesto registra versión, build, SHA fuente, run de build y SHA-256 del APK;
- QA ahora descarga APK + manifiesto y bloquea si versión/build/SHA/hash no coinciden con el gate;
- el gate de +153 fue registrado correctamente sobre SHA `b0093637d363ed3e19b38fc5ab206502bb79976e`;
- la recuperación oficial se integró en `Express Preview Shorebird Code Push` mediante marcador `[recover-preview]`; el workflow provisional separado fue eliminado;
- un QA manual anterior fue cancelado por colisión de concurrencia con el `workflow_run` automático de recuperación; se separaron los grupos para que el run automático saltado no cancele el QA manual;
- el guard de llamadas privadas dio un falso positivo por comparar texto multilinea con espacios exactos; ahora valida semánticamente las tarjetas `_PassengerActiveTripCard` y `_DriverActiveTripCard`, exige `ExpressPrivateVoiceCall.startTripCall` y bloquea `callExpressNumber` dentro de esos bloques;
- el nuevo QA ya pasó resolución de identidad y guard de llamadas privadas;
- no hay regresión funcional de llamadas confirmada en este incidente;
- Producción permanece intacta.

---

## 2026-10-06 · Revisión de app: +152 bloqueada por identidad, +153 lanzada

- Preview +152 terminó Shorebird en success y publicó `app-release.apk`;
- gate de +152 quedó en SHA `c5f397c8ce617b97fb1f3b723f38c6b00c6835c3`;
- QA resolvió correctamente la identidad +152, pero bloqueó porque el tag `preview-shorebird-v1.6.0-build152` apuntaba a `fc47121cce8206ec38b1e8ff43baa0e1e74a7c9d` y no al SHA del build;
- causa raíz: `gh release create` no fijaba `--target "$GITHUB_SHA"`, por lo que el tag podía tomar el HEAD actualizado por commits documentales durante una build larga;
- corrección CI: commit `dd0beb8ca3b8d1ed98e4d1775a370ffc5c2d794b`, el release/tag ahora queda fijado al SHA exacto del workflow;
- +152 queda **no certificada** aunque el APK exista;
- se lanzó nueva base Preview **1.6.0+153** desde `b0093637d363ed3e19b38fc5ab206502bb79976e`;
- código de viaje activo revisado en el SHA de +152: pasajero y conductor usan `ExpressPrivateVoiceCall.instance.startTripCall(...)`; los `tel:` restantes pertenecen a Delivery, no al viaje de pasajeros;
- QA tenía un error secundario de evidencia cuando se bloqueaba temprano y no existía `artifacts/backend`; corregido en commit `b430a40baab8a9096cc316d6b60b0eed430629ae`;
- no hay fallo funcional nuevo confirmado de producto en este incidente;
- Producción permanece intacta.

---

## 2026-10-06 · Handoff maestro para continuidad entre IAs

- se creó `docs/AI_HANDOFF_2026-10-06_MASTER.md` como fuente autoritativa vigente para estado, arquitectura, reglas de producto, Preview/Producción, Shorebird, QA, llamadas, OTP, mapas, flujos de viaje y continuidad;
- `AGENTS.md` ahora obliga a leer primero el handoff maestro y trata handoffs anteriores como historial;
- `docs/DOCUMENTATION_POLICY.md` apunta al handoff maestro del 2026-10-06;
- `docs/PRIVATE_VOICE_CALLS.md` documenta por qué el fix de +151 no se forzó como patch y por qué se creó la nueva base +152;
- regla permanente reafirmada: **CODE CHANGED = DOCS MUST CHANGE**;
- se documentó la regla de artefactos: Preview = **solo APK**; Producción = **APK + AAB**;
- se documentó la cadena de trazabilidad obligatoria: commit → Shorebird → artefacto → release/tag → gate → QA exacto → aprobación → Producción mismo SHA;
- se documentó que cualquier autoaceptación usada por QA es exclusiva de pruebas y no debe convertirse accidentalmente en lógica de Producción;
- se documentaron las reglas funcionales de viaje, conductor, mapas/rutas, llamada privada ZEGOCLOUD, notificaciones, dark mode, OTP, países/monedas y separación Adminexpress;
- se distinguió explícitamente entre **REGLA**, **CONFIRMADO** y **PENDIENTE DE VALIDAR** para evitar que otra IA confunda requisitos solicitados con implementación certificada;
- estado Android al registrar este handoff: candidato `1.6.0+152`, SHA de creación/pinning `c5f397c8ce617b97fb1f3b723f38c6b00c6835c3`, workflow Shorebird aún en `Shorebird base release`, Producción sin cambios;
- los commits exclusivamente documentales posteriores no reiniciaron Shorebird; solo activaron el flujo web, por lo que el build +152 continúa ligado al SHA de aplicación indicado.

---

## 2026-10-05 · Release traceability, QA ordering and mandatory documentation

- candidato Preview actual: **1.6.0+151**;
- se identificó que el nombre visible de un run podía mostrar +151 mientras el `app_release_gate` seguía en +150;
- QA #728 no ejecutó pruebas funcionales: se bloqueó porque `main` declaraba 1.6.0+151 y el gate seguía en 1.6.0+150;
- se identificó además que un workflow Android puede quedar verde sin construir nada; Build Express Android #669 terminó `success` con “No hay builds Android en cola”, por lo que un verde sin artefacto no cuenta como build válido;
- `Express QA Auditor` dejó de dispararse por `push` de app para evitar que corra antes de que Shorebird publique la nueva Preview;
- commit del cambio de orden QA: `c8f3ba3c8b7042ef9b010e87b541faf15e3c6499`;
- la base +151 está vinculada al SHA de app `cb588ae43f81e77152078e0d65f225ced7928dc1`; entre ese SHA y el commit de ajuste QA solo cambia `.github/workflows/express-qa.yml`;
- regla de trazabilidad reforzada: versión + build + SHA + artefacto + tag/release + gate + QA deben coincidir antes de certificar;
- regla Shorebird: si el patch es compatible se conserva la misma base; si falla por diferencias nativas, se crea automáticamente una nueva base Preview limpia en vez de forzar native diffs;
- Preview genera **APK solamente**; Producción genera **APK + AAB**;
- se creó `docs/AI_HANDOFF_2026-10-05_RELEASE_TRACEABILITY.md` como handoff autoritativo vigente;
- se creó `docs/DOCUMENTATION_POLICY.md` con la regla permanente **CODE CHANGED = DOCS MUST CHANGE**;
- todo cambio, incluso pequeño, debe documentarse antes de considerarse terminado o promoverse;
- `AGENTS.md` y `START_HERE_EXPRESS.md` fueron actualizados para obligar a leer la documentación vigente antes de editar.
- `Build Express Android` dejó de ejecutarse por cualquier `push` a `main`; commit `d7d4ccda7db95195c3d250eb894cfe5020d23717`. El builder conserva ejecución manual y sondeo programado, evitando verdes vacíos por cambios documentales.
- gate de +151 reparado con un nuevo build `ready` sin sobrescribir el intento fallido anterior; build id `9319f4b4-decd-40b1-b5b8-b17b6d1c7a06`, SHA `cb588ae43f81e77152078e0d65f225ced7928dc1`;
- `android-build-worker` v29 agrega `preview_base_published` para registrar automáticamente una base Shorebird exacta antes de cerrar el workflow;
- Shorebird falla si versión/build/SHA/APK no quedan reflejados exactamente en el gate; QA ya no puede caer silenciosamente en una Preview anterior;
- QA automático queda atado al SHA del Shorebird que lo dispara y diferencia SHA base de SHA current para soportar patches correctamente;
- cambios exclusivos del workflow Shorebird ya no generan patches automáticos; commit `73d7945aa8ef48b250cb09347bf519fd44187e46`.
- fallo real detectado en Preview +151: la tarjeta principal de viaje activo seguía usando `tel:` mediante `callExpressNumber`, por lo que Android abría Teléfono/Zoom en vez de la llamada privada;
- pasajero y conductor en viajes activos ahora usan `ExpressPrivateVoiceCall.startTripCall(...)` desde la tarjeta principal; commit `df5959499e58cdf258372baa81e2321fd3e3e32b`;
- QA incorpora un guard estático que bloquea el candidato si esas dos rutas vuelven a abandonar ZEGOCLOUD; commit `169a32387c6101a8b7169018d941d3c6dcf7e9f9`.

---

## 1.5.99 · build 144 — OTP telefónico multi-proveedor

- verificación de teléfono migra de Supabase SMS a router propio autenticado;
- Firebase Phone Auth cubre como máximo 10 reservas en cualquier ventana móvil de 24 horas por proyecto Firebase, evitando sobrepasar el tramo gratuito por diferencias de horario;
- al agotar el cupo, Chile queda preparado para LETEL y Bolivia para Unimatrix;
- si faltan credenciales del proveedor secundario, el backend corta el envío y no continúa cobrando Firebase;
- límites antiabuso: 60 s entre reenvíos, topes por usuario/número y máximo de intentos;
- el número verificado se confirma en backend antes de actualizar `phone_verified_at`;
- secretos de LETEL/Unimatrix quedan exclusivamente en Supabase Edge Functions;
- nueva dependencia nativa `firebase_auth`: requiere nueva base Preview antes de QA;
- Producción conserva switches SMS apagados hasta certificación.

## 1.5.98 · build 143 — Cobertura operativa completa

- al apagar un país o una zona, conductores conectados pasan a offline;
- un conductor solo puede conectarse si su GPS está dentro de su zona activa y el país está activo;
- viajes y deliveries disponibles para conductor respetan país/zona activa;
- Producción muestra “Zona no disponible” en vez de un error genérico;
- pasajero, registro de conductor y conductor conectado usan el mismo resolvedor de cobertura (radio/polígono + país + zona).

## 1.5.97 · build 142 — Cobertura global administrable

- países y ciudades dejan de estar codificados a Chile/Bolivia: el backend usa catálogo administrable;
- un país maestro puede activarse/desactivarse sin publicar otra app;
- cada zona puede activar/desactivar registro de conductores;
- GPS fuera de cobertura bloquea el inicio de servicios y muestra “Todavía no hemos llegado a esta zona”;
- registro nuevo de conductor exige GPS dentro de la misma zona activa y ya no permite saltar a otra ciudad manualmente;
- Didit se habilita por país y resuelve Workflow desde configuración segura o `DIDIT_*_WORKFLOW_<ISO2>`;
- la selfie verificada sigue siendo la foto oficial cuando Didit está activo;
- documentos adicionales, como licencia, siguen configurándose por país/zona desde Admin;
- backend versionado en migración `106_global_country_zone_coverage_controls.sql`.


## 1.5.96 · build 141 — Didit Chile en Producción

- Chile (`CL`) usa el flujo de identidad verificada de Didit Production igual que Bolivia.
- La variable esperada en Supabase es `DIDIT_PROD_WORKFLOW_CL`.
- La cédula de identidad manual queda desactivada en Chile para evitar captura duplicada.
- La licencia de conducir continúa como documento adicional obligatorio.
- La selfie verificada por Didit se utiliza como foto de perfil del conductor.
- Producción no debe volver al flujo manual antiguo para Chile mientras el workflow de Didit esté configurado.

# Express — Changelog activo de desarrollo


## 2026-10-06 — Ventana flotante de ofertas — requisito +155

- documentado el requisito de **Ventana flotante de ofertas** para conductores con Express en segundo plano;
- requiere doble control: flag global Admin + activación voluntaria del conductor + permiso Android **Mostrar sobre otras aplicaciones**;
- Admin no puede saltarse ni conceder el permiso del sistema;
- oferta real vigente: Aceptar abre el viaje; Rechazar/expirar/cancelar cierra el overlay;
- no se utilizará una oferta disfrazada como llamada/full-screen intent;
- Preview y Producción deben mantener configuración separada;
- documento: `docs/FLOATING_DRIVER_OFFERS.md`;
- estado: **PENDIENTE DE IMPLEMENTAR**, objetivo funcional +155; no confundir documentación con feature terminada.


## 2026-10-05 · edición aislada del conductor + contexto pasajero por GPS

- **Vehículo y documentos** deja de reutilizar el formulario completo para todos los accesos.
- Cada acceso abre únicamente su sección: **País y zona**, **Documento de identidad**, **Foto de perfil**, **Datos del vehículo** o **Documentos adicionales**.
- Identidad muestra solo la verificación y el estado/foto de perfil asociado; vehículo y documentos ya no exponen atajos a otros pasos.
- Cambiar país/zona del conductor lo deja **pendiente de revisión** y fuera de línea hasta nueva aprobación.
- Foto, vehículo y documentos tienen guardado independiente y revisión independiente del resto del formulario.
- En Pasajero, el GPS resuelve la zona antes de fijar el contexto operativo.
- Si el GPS detecta otra ciudad del mismo país, la zona se actualiza automáticamente.
- Si detecta otro país, Express pide confirmación antes de cambiar moneda, billetera, precios y métodos de pago.
- Si el GPS no está disponible, el pasajero puede reintentar o elegir manualmente su ubicación en el mapa.
- Crear un viaje ya no puede cambiar de país silenciosamente: exige que el cambio haya sido confirmado desde Inicio.

---

## v1.5.93 · build 138 — Didit nativo dentro de Express

- Didit deja de abrir Chrome durante el registro de conductor.
- Integración Flutter nativa con `didit_sdk_autodetection`: documento, prueba de vida y coincidencia facial permanecen dentro de Express.
- El cliente recibe únicamente el `session_token` efímero creado por `didit-identity`; la API key y Workflow IDs continúan solo en Supabase.
- Al cerrar el SDK, Express reconcilia el resultado contra Didit/Supabase antes de mostrar aprobación; el callback local no se trata como fuente autoritativa.
- `refresh` ya no depende de que la ciudad del onboarding se haya guardado, evitando el 409 visto al regresar de una verificación.
- Webhook reforzado: valida timestamp y firma HMAC; acepta V2 canónica y la firma raw oficial como fallback criptográfico.
- Sesiones webhook desconocidas ya no pueden crear verificaciones usando solo `vendor_data`.
- Android mínimo pasa a API 23, requisito del SDK nativo.
- Este cambio agrega una dependencia nativa: requiere una **nueva base Preview**; no puede distribuirse como simple patch Shorebird sobre la base anterior.
- Producción permanece sin promover hasta completar Preview → QA → aprobación → mismo SHA.


---

## Páginas legales en dominio Express

- dominio público confirmado de Expressdelivery: `https://expressviajes.online/`;
- nuevas URLs limpias:
  - `https://expressviajes.online/privacidad/`
  - `https://expressviajes.online/terminos/`
  - `https://expressviajes.online/eliminar-cuenta/`
- se mantienen `privacy.html`, `terms.html` y `delete-account.html` por compatibilidad;
- botones legales de la app y Centro de privacidad apuntan al dominio Express;
- Google Play submission documenta las URLs nuevas;
- no se modifica DNS ni Producción Android.

---

## v1.5.91 · build 135 · Google Auth habilitado en Preview

- Google OAuth ya estaba implementado en `auth_entry.dart`, pero la bandera `EXPRESS_GOOGLE_AUTH_ENABLED` se compilaba en `false` y ocultaba el botón;
- Preview Shorebird y el parche manual ahora compilan Google Auth en `true`;
- el valor por defecto de la app pasa a `true` para Web;
- futuros builds Android usan `true` cuando la variable de GitHub no está definida;
- se fuerza una nueva base Preview `1.5.91+135` porque `1.5.90+134` nunca tuvo release Shorebird y no podía recibir patch;
- Producción Android no se genera automáticamente.

---

## v1.5.90 · build 134 · cuenta única Pasajero/Conductor

Objetivo: una sola identidad Express por correo, con Conductor como capacidad opcional de la misma cuenta.

- registro nuevo sin selector Cliente/Conductor; todas las cuentas nuevas entran como Pasajero;
- perfil muestra **Conducir con Express**, **Continuar registro de conductor** o **Cambiar a modo Conductor** según el estado real;
- al intentar entrar a Conductor se abre el onboarding si faltan datos/vehículo y se mantiene al usuario como Pasajero mientras la aprobación está pendiente;
- `active_mode` se sincroniza por Realtime entre dispositivos para evitar sesiones visualmente desactualizadas;
- `ratings.rated_role` separa reputación de Pasajero y Conductor;
- 50 calificaciones históricas migradas sin pérdida: 25 Conductor + 25 Pasajero;
- prioridad del conductor usa solo calificaciones como Conductor;
- ranking de pasajeros usa solo calificaciones como Pasajero;
- Admin detalle de conductor/usuario también separa ambos resúmenes;
- migración `098_unified_account_role_reputation.sql` aplicada y verificada;
- Producción Android no se publica automáticamente; candidato sujeto a Preview/QA.

---

## v1.5.89 · build 133 · reducción de consumo Supabase/logs

Objetivo: reducir requests repetitivos que elevaban Log Ingestion/Log Query sin perder actualizaciones críticas de viaje.

- diagnóstico de las últimas 24 h: la mayor fuente era el gateway (`edge_logs`), dominado por dos clientes Android;
- Realtime y push siguen siendo la vía primaria para ofertas/estados;
- respaldo de ofertas de pasajero pasa de 900 ms a 2 s y solo consulta mientras existe una solicitud abierta;
- respaldo crítico de pasajero pasa de 1.4 s a 3 s;
- polling de respaldo del conductor pasa de 5 s a 12 s;
- `my_viewed_ride_request_ids` deja de consultarse en cada refresco y se carga una sola vez por sesión de Home;
- prioridad del conductor usa caché de 1 minuto;
- calificación pendiente del conductor usa caché de 30 s;
- `cleanup_expired_ride_requests` deja de ejecutarse en cada lectura de solicitudes porque el RPC ya filtra expiradas;
- GPS conserva actualización local continua, pero la escritura remota se limita a ~3 s con servicio activo y ~10 s mientras espera online;
- `updateDriverDetails` ya no relee `driver_profiles` antes de cada escritura GPS;
- no se generó APK/AAB de Producción; el candidato debe pasar Preview/QA.

---

## v1.5.88 · build 132 · aislamiento runtime Pasajero/Conductor

Objetivo: mantener Pasajero y Conductor dentro de una sola app sin dejar procesos ni disponibilidad del conductor activos al cambiar de rol.

- respaldo previo: `backup/2026-10-04-role-runtime-isolation-pre` desde `de72cbae6066ed4df3e102e888a07be36f902642`;
- rama de trabajo: `feature/097-role-runtime-isolation`;
- cambiar de Conductor a Pasajero deja al conductor `offline` de forma autoritativa en Supabase;
- el backend bloquea un cambio a Pasajero si existe viaje o delivery activo;
- un perfil solo puede entrar en `online/busy` cuando la cuenta está activa y en `active_mode=driver`;
- el dispatch/push de solicitudes exige además `active_mode=driver`, evitando que un pasajero reciba solicitudes por un estado viejo;
- se limpian perfiles `online` incompatibles sin tocar servicios activos;
- `DriverMapHome` reactiva GPS continuo al reconstruirse durante un servicio activo;
- el tracking se cancela si el conductor queda fuera de línea;
- al salir del shell Conductor se siguen cancelando timers, streams y canales Realtime;
- Producción Android 1.5.87+131 permanece sin reemplazar hasta que este candidato pase Preview/QA y sea aprobado.

---

## 2026-10-04 — Handoff IA, branding, SMS, pagos y laboratorio QA

- se agregó `AGENTS.md` y `docs/AI_HANDOFF_2026-10-04.md` como documentación autoritativa para futuras IAs/agentes;
- Producción Android vigente documentada como `1.5.87+131`, SHA aprobado `45c2aff26cd27229e445461d2f129023bf6f60df`;
- marca global unificada a **Express** y logo oficial protegido/reutilizable;
- verificación SMS separada para Pasajeros y Conductores, ambos switches OFF por defecto;
- Chile: CLP y viajes en efectivo; Bolivia: BOB y viajes en efectivo + QR del conductor;
- Mercado Pago administrativo reservado para suscripciones/recargas, no tarifa ordinaria de viaje;
- aislamiento runtime `preview` / `production` consolidado;
- laboratorio QA corregido para channel correcto, CLP en Iquique, cleanup aislado y errores legibles;
- laboratorio QA ahora soporta `mixed`, `car` y `motorcycle`;
- escenario QA de Iquique validado con Auto/Moto y visibilidad correcta en pasajero;
- se documentó que un QA rojo puede ser infraestructura/harness y debe leerse el verdict antes de clasificarlo como fallo de producto.

---

## Express Delivery V2 · UI/flujo V4

Objetivo: cerrar los problemas detectados en la revisión guiada posterior a
Preview 1.5.83+127.

- respaldo: `backup/pre-delivery-polish-v4-2026-10-03` desde
  `826f22d96d74a2b0334749464baa7bad94fdad47`;
- Atrás en Viajes/Delivery vuelve al selector principal;
- Viajes incluye acceso lateral directo a Restaurantes;
- menú lateral deja de reservar altura vacía;
- se eliminan accesos redundantes del Home Delivery;
- banners, Promo y Carrito corregidos para claro/oscuro y Preview Shorebird;
- restaurante amplía imagen; horario/opiniones ausentes se representan solo
  como contenido DEMO de Preview;
- carrito muestra sugeridos reales del local, subtotal, volver al local e ir a
  pagar;
- checkout permite seleccionar o crear dirección y actualiza su mini-mapa;
- pedido creado abre seguimiento vivo;
- Pedidos permite abrir el detalle/estado de cada pedido;
- seguimiento muestra mapa, local, cliente, repartidor, etapas, productos,
  pago, total y código de entrega, ocultando mapa al finalizar/cancelar;
- Producción continúa sin modificaciones.

---

## Express Delivery V2 · UI polish V3

Objetivo: corregir la revisión visual guiada posterior al primer Preview V2 y compactar la experiencia tomando lo mejor de las dos referencias mostradas.

Cambios:

- backup previo exacto: `backup/pre-delivery-ui-polish-2026-10-04` desde `7534f12d5b25eb99a21f4ecba1d5f5f561e4ed2d`;
- elimina la doble barra inferior al entrar a Express Delivery, incluso si Marketplace es el módulo predeterminado;
- añade selector lateral izquierdo para Viajes Express / Restaurantes / Conductor y regreso al selector de servicios;
- añade accesos directos compactos Viaje Express / Restaurantes dentro del Home;
- fuerza iconos y contraste en la navegación inferior Delivery;
- aplica superficies/textos/bordes adaptativos a modo claro y oscuro;
- corrige el selector de país/zona, tabs de restaurante, opiniones, producto, notas, cantidades y carrito en dark mode;
- categorías admiten dos líneas y dejan de cortar nombres;
- reemplaza el icono ambiguo del producto por un chevron “Ver producto”;
- compacta restaurante, producto, banners y carruseles para reducir scroll;
- carrito muestra comercio, ítems, extras, notas, cantidades, unitario y total;
- checkout añade mini-mapa comercio→cliente;
- instrucciones y propinas quedan en una sola fila horizontal;
- métodos de pago pasan a tarjetas horizontales con selección animada;
- facturación y donación pasan a acciones compactas;
- no cambia backend comercial, monedas, zonas, cupones ni reglas financieras;
- Producción continúa protegida y OFF.


Este archivo resume las versiones recientes que cambiaron la arquitectura o el comportamiento de la aplicación.

> Para arquitectura, backend, roadmap y handoff completo, leer primero:
> `docs/START_HERE_EXPRESS.md`

---

## Express Delivery V2 · Preview activo

Objetivo: consolidar los dos recorridos de referencia revisados el 3 de octubre en una experiencia Delivery multi-zona/multi-país, manteniendo Producción protegida.

Cambios:

- respaldo exacto creado antes de V2 para App y AdminExpress;
- nueva experiencia `ExpressDeliveryV2Page` con Inicio / Mercados / Promos / Pedidos / Perfil;
- selector de país/zona y direcciones geocodificadas;
- notificaciones, pedidos, facturación y preferencias aislados por país;
- categorías con filtros, productos transversales y tags;
- comercio con Menú / Opiniones / Información y secciones internas;
- producto con promociones, modificadores/extras, reglas mínimo/máximo, nota y reseñas;
- carrito persistente, venta cruzada y último paso de checkout;
- cupón, propina, prioridad, instrucciones, facturación, donación y métodos de pago por zona;
- PIN seguro de entrega y reseñas verificadas;
- Home dinámico con secciones programables, patrocinados y skeleton loading;
- AdminExpress V2 para Home, cupones, menús, modificadores, promociones, venta cruzada y comercio;
- migraciones candidatas 085–088 aditivas, con RLS/permisos explícitos;
- QA SQL con rollback confirma aislamiento CL/CLP vs BO/BOB, cupones por zona, extras obligatorios, PIN y separación de pedidos/notificaciones;
- migraciones 085–088 aplicadas para Preview y verificadas por país/zona;
- Producción Marketplace permanece OFF.

Documentación completa: `docs/EXPRESS_DELIVERY_V2_IMPLEMENTATION.md`.

---

## v1.5.69 · build 110 · siguiente parche Shorebird

Objetivo: pulir el flujo map-first de pasajero/conductor y corregir las inconsistencias visuales detectadas en la revisión guiada del 1 de octubre.

Cambios:

- el mapa principal centra al usuario con una vista inicial más consistente y los vehículos cercanos reducen su tamaño al alejar el zoom, recuperando su tamaño normal al acercar;
- el selector de destino deja de mostrar el SnackBar inferior cuando origen y destino coinciden; conserva el mensaje inline y añade una guía animada que enseña a mover el mapa;
- la búsqueda de direcciones recibe una barra visual renovada, debounce más corto y sugerencias visibles al escribir o al pulsar buscar, sin seleccionar automáticamente la primera coincidencia;
- al solicitar un viaje, la transición visual entra directamente en “Ofreciendo tu tarifa”, evitando el doble estado “Buscando conductor”;
- las ofertas del conductor muestran el contador real de hasta 30 segundos en vez de truncarlo visualmente a 15 segundos;
- el panel activo del pasajero queda bloqueado a una altura adaptada a la etapa del viaje: crece cuando aparecen acciones como Cancelar y se compacta durante el viaje para no dejar espacio vacío;
- el panel del conductor y la espera de confirmación respetan el modo oscuro;
- Inicio / Historial / Pagos / Perfil mantienen la navegación inferior en las vistas principales; durante la preparación o un viaje activo se oculta, el menú se convierte en botón de regreso y el proceso puede minimizarse sin cancelar el viaje, dejando un acceso compacto para volver al seguimiento;
- Historial y detalle de viaje usan superficies, bordes, textos y contrastes adaptativos para modo claro/oscuro;
- la experiencia conectada usa un tema adaptativo al modo del sistema y corrige el índice de Perfil del pasajero;
- se mantiene la base Preview 1.5.69+110 para publicar estos cambios como parche Shorebird sobre la instalación existente; no se genera APK/AAB automáticamente.

---

## v1.5.48 · build 89

Objetivo: cerrar definitivamente la recepción visual de ofertas del conductor en la pantalla del pasajero.

Cambios:

- las filas de `driver_offers` recibidas por Supabase Realtime se aplican inmediatamente al estado visual del pasajero, sin esperar al siguiente RPC;
- `passenger_home_state()` y el sondeo cada 2 segundos se mantienen como respaldo y enriquecimiento de perfil/conductor;
- se elimina el borrado del estado de oferta legado que ocurría en cada refresco y podía interferir con la experiencia;
- la bandeja de ofertas conserva cada presentación durante 15 segundos;
- las reofertas del mismo conductor se agregan debajo como una nueva presentación sin pisar la anterior;
- al vencer una presentación antigua no se rechaza una reoferta más nueva del mismo conductor;
- se fuerza marcador de versión web y service worker a v1.5.48 build 89 para evitar probar código cacheado;
- verificado en Supabase LIVE que `driver_offers` está en la publicación Realtime, que el pasajero tiene política SELECT sobre sus ofertas y que `passenger_home_state()` devuelve ofertas `pending` vigentes;
- no se genera APK/AAB automáticamente.

---

## v1.5.35 · build 76

Objetivo: cerrar el flujo de recepción de solicitudes del conductor y llevar la alerta entrante a una experiencia de pantalla completa.

Cambios:

- solicitud entrante del conductor pasa a modal de pantalla completa sobre el mapa;
- el mapa encuadra conductor, origen y destino al abrir la solicitud;
- se dibuja ruta conductor → origen y origen → destino mientras se revisa la solicitud;
- popup automático mantiene temporizador de 45 segundos;
- se muestran tarifa del pasajero, categoría, distancia al origen, ETA, distancia/tiempo del viaje, forma de pago, origen y destino;
- agregado botón principal “Aceptar por Bs …”;
- agregados tres montos rápidos para contraofertar y opción “Ofertar otro monto”;
- “Cerrar solicitud” cierra el popup sin borrar la solicitud activa del pasajero;
- cuando no hay solicitudes, el panel de Inicio del conductor queda más bajo y compacto;
- agregado quinto acceso en navegación: “Solicitudes”, con badge/contador de solicitudes activas;
- la nueva bandeja de Solicitudes muestra solicitudes activas y su tiempo restante;
- desde la bandeja se puede aceptar la tarifa del pasajero o enviar otra oferta;
- el conductor deja de depender del SELECT directo de ride_requests: se agregó RPC de despacho para devolver solicitudes abiertas a conductores aprobados y en línea;
- se verificó en Supabase que un conductor aprobado/en línea recibe una solicitud activa mediante el nuevo RPC;
- se verificó en una transacción de prueba revertida que una oferta insertada aparece en passenger_home_state();
- durante preview se permite ver la solicitud creada por la misma cuenta al cambiar Pasajero ↔ Conductor, para facilitar pruebas; la asignación real sigue protegida en backend;
- no se genera APK/AAB automáticamente.

---

## v1.5.34 · build 75

Objetivo: completar el flujo posterior a aceptar una oferta y acercarlo al flujo de referencia Pasajero/Conductor.

Cambios:

- pasajero ve una tarjeta completa del conductor asignado con estado, ETA aproximada, calificación, viajes completados, vehículo y patente;
- se muestra foto/avatar del conductor cuando existe;
- se genera un PIN de abordaje de 4 dígitos por viaje;
- el PIN se muestra al pasajero antes de iniciar el viaje;
- el conductor debe ingresar el PIN correcto para pasar de “Llegué” a “Viaje en curso”;
- el backend bloquea el inicio del viaje sin validar el PIN;
- se mantienen Mapa, Chat y Llamar y se agregan Compartir viaje y Emergencia/SOS para el pasajero;
- Compartir intenta abrir WhatsApp y, como respaldo, copia los datos del viaje;
- SOS registra una emergencia asociada al viaje;
- el panel activo del conductor ahora muestra pasajero, ruta, tarifa, estado y acciones principales;
- cuando el conductor está esperando, la UI recuerda pedir el PIN antes de iniciar;
- el mapa de seguimiento dibuja Conductor → origen mientras va a buscar al pasajero;
- durante el viaje, el seguimiento usa Conductor → destino cuando hay ubicación en tiempo real;
- el seguimiento muestra distancia y ETA aproximada;
- la pantalla secundaria de Servicios del conductor también exige PIN para iniciar;
- no se genera APK/AAB automáticamente.

---

## v1.5.33 · build 74

Objetivo: corregir duplicación de solicitudes en modo Conductor y alinear la bandeja con el flujo de referencia.

Cambios:

- la solicitud prioritaria sigue apareciendo como popup automático;
- se elimina la tarjeta duplicada de la misma solicitud dentro del panel inferior;
- el panel del conductor ahora muestra un único botón “Solicitudes” con contador de solicitudes activas;
- al tocar “Solicitudes” se abre una bandeja con todas las solicitudes vigentes;
- tocar una solicitud de la bandeja vuelve a abrir su popup de detalle;
- el contador se actualiza según las solicitudes activas;
- un conductor ya no puede ver ni responder una solicitud creada por esa misma cuenta en modo Pasajero;
- no se genera APK/AAB automáticamente.

---

## v1.5.32 · build 73

Objetivo: completar la renovación de rondas para que una búsqueda continuada vuelva a ser visible como nueva para los conductores.

Cambios:

- al continuar otros 3 minutos se limpian las marcas de visualización de la ronda anterior;
- los conductores pueden volver a recibir popup automático de esa solicitud renovada;
- la lista de solicitudes sigue conservando el acceso manual;
- se renueva el marcador de caché Web para publicar todos los cambios de despacho;
- no se genera APK/AAB automáticamente.

---

## v1.5.31 · build 72

Objetivo: cerrar el flujo de despacho tipo marketplace entre Pasajero y Conductor.

Cambios:

- “Elige tu viaje” queda estático; solo la lista interna de categorías/servicios se desplaza;
- solicitudes del conductor aparecen automáticamente como popup individual de 45 segundos;
- solo se muestra un popup a la vez;
- prioridad automática: solicitud más cercana y, en empate, la más antigua;
- el popup automático solo considera solicitudes dentro de 10 km cuando hay GPS;
- al cerrar o vencer un popup, se muestra la siguiente solicitud pendiente;
- las solicitudes vistas no vuelven a abrirse automáticamente para ese conductor;
- la lista “Solicitudes cerca de ti” conserva todas las solicitudes vigentes y permite reabrir cualquier popup manualmente;
- pasajero recibe ofertas del conductor como popup sobre el mapa, no dentro de la tarjeta inferior;
- cada oferta visible dura 15 segundos, con aceptar/rechazar y cola secuencial;
- ofertas revisadas por el mismo conductor pueden volver a mostrarse si cambia su vigencia;
- ronda de búsqueda del pasajero reducida a 3 minutos;
- al llegar a cero se pregunta si desea seguir 3 minutos, subir oferta o cancelar;
- si no responde la decisión, la solicitud se cancela;
- si abandona la app/pantalla durante esa decisión, se solicita cancelación y, además, el backend deja de mostrar la solicitud a conductores al vencer;
- backend conserva una gracia corta para permitir renovar la ronda y luego cancela solicitudes abandonadas;
- ofertas del conductor mantienen una ventana backend de 30 segundos para garantizar 15 segundos completos de visualización en UI;
- refresco Pasajero/Conductor reducido a 2 segundos durante esta etapa de pruebas;
- no se genera APK/AAB automáticamente.

---

## v1.5.30 · build 71

Objetivo: ajustar la pantalla “Confirma tu ruta” al espacio real disponible en cada sistema de navegación.

Cambios:

- la confirmación de ruta deja de reservar siempre el 50% de la pantalla;
- la altura se calcula según el alto real del dispositivo;
- navegación por gestos: el panel baja y elimina espacio vacío debajo del CTA;
- navegación Android por 3 botones: el panel se eleva automáticamente para respetar la barra del sistema;
- Web: la tarjeta queda más compacta y ajustada al contenido;
- el padding inferior de “Confirmar ruta y continuar” también se adapta al sistema;
- al volver desde “Elige tu viaje” se recupera la altura correcta de confirmación;
- el encuadre del mapa usa la nueva altura del panel;
- no se genera APK/AAB automáticamente.

---

## v1.5.29 · build 70

Objetivo: estabilizar el despacho Pasajero/Conductor, corregir autoaceptación y encuadrar el panel del conductor.

Cambios:

- corregido el filtro de solicitudes del conductor cuando aún no existe un vehículo activo;
- un conductor sin vehículo cargado ya no queda con la lista vacía durante pruebas/onboarding;
- las ofertas del conductor duran 2 minutos en vez de 20 segundos;
- autoaceptación del pasajero se ejecuta inmediatamente al activar el switch si ya hay ofertas;
- autoaceptación prioriza ofertas iguales o menores a la tarifa del pasajero y luego menor ETA;
- pasajero y conductor refrescan solicitudes/ofertas cada 4 segundos;
- el modo conductor abre su panel en una altura estable y coherente con sus snap points;
- el panel del conductor ya no reinicia a una posición intermedia que tape “Solicitudes cerca de ti”;
- agregado botón de un toque “Aceptar tarifa” para enviar la misma tarifa propuesta por el pasajero;
- se mantiene “Ofertar otro monto” para contraofertas;
- corregido el caso de calificación a la misma cuenta durante pruebas Pasajero/Conductor;
- backend actualizado para extender el vencimiento predeterminado de ofertas y omitir auto-calificación;
- no se genera APK/AAB automáticamente.

---

## v1.5.28 · build 69

Objetivo: encuadrar la selección de servicios y evitar que opciones o acciones queden cortadas.

Cambios:

- nueva hoja de “Elige tu viaje” inspirada en la referencia visual;
- al entrar, la hoja abre en 68% de la pantalla;
- puede bajar hasta 58% y subir hasta 92%;
- cabecera, tarifa y acciones principales quedan encuadradas;
- la lista de servicios es la zona desplazable para ver Express, Comfort, XL, Moto y futuros servicios;
- “Cuándo”, “Pago” y el botón de confirmar quedan fijos en la parte inferior;
- nuevo control de tarifa con botones menos/mas y edición directa;
- el mapa se reencuadra usando la altura real de la hoja de servicios;
- tarjetas de servicio usan el azul oficial Express;
- no se genera APK/AAB automáticamente.

---

## v1.5.27 · build 68

Objetivo: corregir definitivamente el marcador del punto de encuentro y eliminar los CTA naranjas del flujo de taxi.

Cambios:

- botones principales “Confirmar Express” y “Solicitar” usan azul Express;
- el marcador del punto de encuentro queda fijo visualmente en el centro del mapa;
- al mover el mapa se actualiza el punto real de recogida según el centro visible;
- al detener el mapa se ejecuta reverse geocoding y se actualiza la dirección;
- “Solicitar” queda deshabilitado mientras el mapa todavía se está moviendo o resolviendo la dirección;
- el botón de recentrado vuelve al último punto confirmado;
- se evita confirmar una coordenada distinta del marcador visible;
- no se genera APK/AAB automáticamente.

---

## v1.5.26 · build 67

Objetivo: unificar las pantallas de ubicación con el tema visual de Express y estabilizar el encuadre previo a solicitar conductor.

Cambios:

- agregado tema oscuro global para Web y Android según el modo del sistema;
- selector de ubicación y confirmación de punto de encuentro usan la misma paleta Express;
- la pantalla de punto de encuentro ya no vuelve a blanco cuando el dispositivo está en modo oscuro;
- el mapa de confirmación aplica el mismo tratamiento oscuro usado por el Home;
- dirección, botón Cambiar, controles de mapa y superficies se adaptan a claro/oscuro;
- se conserva azul Express para acciones secundarias y naranja para el CTA final Solicitar;
- el panel “Elige tu viaje” queda fijado al 50% mientras se configura el viaje;
- el panel principal sin destino continúa fijo al 42%;
- la cámara de la ruta usa mayor padding inferior y lateral para dejar visibles origen, destino y ubicación del pasajero por encima del panel;
- la ruta se vuelve a encuadrar al confirmar sin expandir el panel;
- no se genera APK/AAB automáticamente.

---

## v1.5.25 · build 66

Objetivo: aplicar las nuevas referencias visuales al flujo de ubicación/viaje y dejar temporalmente la experiencia pública en modo solo taxi.

Cambios:

- rediseñado el selector de destino con mapa a pantalla completa, buscador flotante y panel inferior redondeado;
- eliminadas las coordenadas GPS visibles al pasajero;
- el destino muestra dirección legible, botón Cambiar, ayuda breve y “Confirmar el destino”;
- antes de crear la solicitud se abre una pantalla específica para confirmar el punto de encuentro;
- la pantalla de recogida muestra mapa, dirección, botón Cambiar y CTA “Solicitar”;
- al confirmar “Solicitar” se crea recién la solicitud y comienza la búsqueda de conductores;
- la selección de servicio adopta tarjetas verticales inspiradas en la referencia de video;
- “Pon tu precio” queda visible como acción de edición de la oferta;
- opciones de viaje Express / Comfort / XL / Moto se presentan como lista seleccionable;
- Delivery queda oculto de los flujos nuevos de pasajero y conductor durante esta etapa;
- el backend y código histórico de Delivery se conservan para reactivarlo más adelante;
- textos de login, splash e interfaz pública se ajustan temporalmente a Viajes;
- no se genera APK/AAB automáticamente.

---

## v1.5.24 · build 65

Objetivo: eliminar el vacío visual entre el splash y el Home del pasajero y fijar la altura del panel principal.

Cambios:

- el splash entrega al Home el estado de pasajero que ya fue precargado;
- “Buenos días / ¿A dónde vas?”, buscador y Lugares guardados están disponibles desde el primer frame del mapa;
- el Home deja de esperar una segunda consulta antes de dibujar su contenido inicial;
- el refresco completo continúa en segundo plano para completar datos secundarios;
- el panel principal del pasajero queda fijo en 42% de la pantalla;
- el panel inicial ya no se puede subir ni bajar;
- búsqueda, ruta y servicio activo conservan sus alturas dinámicas cuando corresponde;
- no se genera APK/AAB automáticamente.

---

## v1.5.23 · build 64

Objetivo: mover la comprobación inicial del servicio al splash y eliminar el estado técnico de verificación sobre el mapa.

Cambios:

- nuevo splash animado de Express con entrada de logo y marca;
- el splash se muestra al abrir Web y Android;
- mientras el splash está visible se carga el perfil y se precarga `passenger_home_state()`;
- el Home consume ese estado precargado al entrar;
- eliminado del mapa el panel “Verificando tu servicio…” y su temporizador;
- se evita un segundo loader de cuenta antes de mostrar la experiencia conectada;
- si la precarga falla, el Home conserva su reintento normal sin bloquear la sesión;
- no se genera APK/AAB automáticamente.

---

## v1.5.22 · build 63

Objetivo: simplificar el Home del pasajero según la referencia visual enviada.

Cambios:

- retirado “Viajes recientes” del panel principal;
- retirada la barra inferior fija Viaje/Delivery del Home;
- el panel inicial deja únicamente saludo, “¿A dónde vas?”, buscador y Lugares guardados;
- Casa y Trabajo permanecen como accesos rápidos;
- el selector Viaje/Delivery aparece después de escoger destino para no perder funcionalidad;
- panel inicial más bajo para dejar más mapa visible.

---

## v1.5.21 · build 61

Objetivo: corregir el caso reproducido en video donde el backend cancelaba correctamente el viaje, aparecía “Viaje cancelado correctamente”, pero el panel “Buscando conductores” seguía visible y su contador continuaba.

Cambios:

- se verificó nuevamente en la base LIVE que la solicitud mostrada en el video sí cambia a `cancelled`;
- después de una cancelación confirmada ya no se intenta reciclar el mismo estado de `PassengerMapHome`;
- el Home del pasajero se desmonta completamente y se crea una instancia nueva;
- el `DraggableScrollableSheet`, el estado interno de `_OffersCard` y su temporizador quedan destruidos al cancelar;
- la nueva instancia consulta nuevamente `passenger_home_state()`, que ya no devuelve la solicitud cancelada;
- el reset duro se aplica también a cancelación de viaje asignado y delivery;
- se incrementó un `passengerHomeEpoch` en el shell del pasajero para garantizar que Flutter no reutilice el State anterior;
- esta release es únicamente web/QA por ahora: no genera APK/AAB automáticamente.

---

## v1.5.20 · build 60

Nota operativa: el build 60 automático fue cancelado antes de generar una release. Desde este punto los pushes ya no disparan APK/AAB; Android se compila únicamente desde una solicitud iniciada por Adminexpress.

Objetivo: limpiar Express después de separar Adminexpress y corregir de forma estructural la cancelación que podía quedar visualmente atrapada en “Buscando conductores”.

Cambios:

- `Expressdelivery` queda reservado a Pasajero + Conductor + Delivery;
- retirados `admin_panel.dart` y `admin_control_sections.dart`;
- retirada la antigua entrada `lib/main.dart`;
- retirados modelos/servicios del prototipo antiguo de órdenes;
- retirados previews antiguos de login, viajes, delivery y experiencia;
- eliminado un shell duplicado que creaba una dependencia circular entre Centro Express y la experiencia conectada;
- la configuración de vehículo/documentos del conductor se conserva y queda accesible desde Perfil → Vehículo y documentos;
- `lib/web_preview.dart` deja de reconocer rutas Admin (`?admin=1`, `#admin`, etc.);
- Adminexpress pasa a ser el único frontend administrativo;
- la cancelación mantiene tombstones locales por ID para que un snapshot antiguo nunca pueda volver a dibujar un servicio cancelado;
- una trip antigua ligada al `ride_request_id` cancelado también se oculta;
- `cachedData` es ahora la fuente visual de verdad del Home del pasajero, evitando que `FutureBuilder` restaure datos de una Future anterior;
- si la cancelación realmente falla en backend, se elimina el tombstone y se restaura el servicio;
- se verificó nuevamente la base LIVE: la solicitud más reciente observada pasó correctamente a `cancelled`, confirmando que el fallo reproducido en video era de estado visual;
- documentación actualizada para dejar clara la separación Express/Adminexpress;
- preparada nueva release Android build 60.

---

## v1.5.19 · build 56

Objetivo: corregir definitivamente el caso donde la cancelación se confirmaba en backend pero el panel de “Buscando conductores” seguía vivo con su contador.

Cambios:

- se invalidan cargas antiguas del estado del pasajero mediante revisiones secuenciales;
- una respuesta de red iniciada antes de cancelar ya no puede volver a inyectar una solicitud antigua en la UI;
- al cancelar se fuerza una reconstrucción completa del panel inferior;
- el temporizador interno de “Buscando conductores” se desmonta al cambiar al panel principal;
- después de la confirmación del backend se fuerza nuevamente el panel principal;
- se mantiene el bloqueo visual de la solicitud cancelada hasta que una carga actual confirme que ya no existe;
- se verificó en base de datos que las solicitudes de prueba sí estaban cambiando a estado cancelled, por lo que el fallo era exclusivamente de sincronización visual.

---

## v1.5.18 · build 55

Objetivo: eliminar los saltos visuales entre paneles durante creación/cancelación y mantener visibles todos los controles de búsqueda en móvil.

Cambios:

- al tocar “Buscar conductores” se crea inmediatamente un estado optimista de búsqueda;
- ya no aparece por un instante el panel principal antes de pasar a “Buscando conductores”;
- FutureBuilder prioriza el estado optimista mientras llega la respuesta nueva del backend, evitando reapariciones de pantallas antiguas;
- al cancelar, el viaje desaparece de la UI y vuelve al panel principal sin esperar a que finalice un refresco de red;
- la solicitud cancelada permanece bloqueada en la UI hasta que el backend confirma que ya no está activa;
- se evita que un refresco automático vuelva a mostrar temporalmente una solicitud ya cancelada;
- el panel de búsqueda aumenta su altura inicial y su rango de expansión para que “Aceptar automáticamente” y “Cancelar búsqueda” queden visibles;
- se agregó margen inferior según el área segura del dispositivo/navegador;
- el mapa continúa centrado en el punto de recogida durante la búsqueda.

---

## v1.5.17 · build 54

Objetivo: terminar de alinear el flujo visual del video con el tipo de vehículo real y simplificar la cancelación del cliente.

Cambios:

- el filtro del mapa durante una búsqueda usa la categoría guardada en la solicitud activa, incluso después de recargar la página;
- el vehículo activo guardado por el conductor es la fuente de verdad para mapa y solicitudes disponibles;
- al guardar un vehículo, los demás vehículos del conductor quedan inactivos para evitar tipos duplicados en el despacho;
- Moto muestra motos, XL muestra XL y Express/Comfort muestran autos;
- radar del mapa reforzado con barrido giratorio, pulsos concéntricos y punto central del pasajero;
- la cancelación dejó de usar un selector obligatorio;
- nuevo panel inferior de cancelación adaptado a móvil y modo oscuro;
- el motivo es opcional y el cliente puede tocar directamente “Cancelar ahora”;
- se conserva la verificación posterior contra backend para impedir que un viaje cancelado reaparezca por el refresco automático.

---

## v1.5.16 · build 53

Objetivo: sincronizar el tipo de vehículo elegido por el pasajero con los vehículos realmente guardados por los conductores y corregir la cancelación que podía quedar visualmente pegada.

Cambios:

- el mapa filtra los vehículos cercanos por la categoría seleccionada;
- Moto muestra únicamente conductores con vehículo activo guardado como motorcycle;
- XL muestra únicamente conductores con vehículo activo guardado como xl;
- Express y Comfort muestran conductores con vehículo activo guardado como car;
- cambiar de categoría refresca inmediatamente los vehículos del mapa;
- el conductor sólo recibe solicitudes compatibles con su vehículo activo guardado;
- se conserva el diseño visual específico de auto, moto y XL en el mapa;
- la cancelación oculta inmediatamente la solicitud/viaje mientras se procesa;
- la UI mantiene un bloqueo temporal para que el refresco de 8 segundos no vuelva a mostrar un servicio que se está cancelando;
- después de cancelar, el cliente verifica el estado real del backend;
- si la respuesta de red falla pero el backend sí canceló, la UI reconoce la cancelación y no restaura el servicio;
- cancelación robusta aplicada a búsqueda de viaje, viaje activo y delivery.

---

## v1.5.15 · build 52

Objetivo: acercar la búsqueda visual de conductores a la referencia enviada, manteniendo datos reales de Express.

Cambios:

- radar grande animado directamente sobre el mapa durante la búsqueda;
- vehículos rediseñados en vista superior, con sombra, orientación visual y microanimación;
- auto, moto y XL mantienen diseños diferenciados;
- los vehículos mostrados siguen siendo conductores reales aprobados y en línea;
- estados dinámicos de búsqueda: “Buscando conductores”, “Ofreciendo tu tarifa”, “Esperando respuestas” y “Buscando más opciones”;
- contador y barra de progreso visibles durante la búsqueda;
- mini fotos de perfil de los conductores que ya vieron la solicitud, superpuestas y con contador +N;
- las fotos y nombres provienen de los perfiles reales de los conductores;
- tarjetas de ofertas rediseñadas con foto, nombre, calificación, viajes completados, vehículo, ETA y tarifa;
- aceptar/rechazar conserva expiración de 20 segundos;
- opción “Aceptar automáticamente al más cercano”, basada en menor ETA y luego menor tarifa;
- backend incorpora RPC seguro para devolver los perfiles de quienes vieron una solicitud;
- las ofertas del pasajero ahora incluyen identidad básica del conductor para la tarjeta visual;
- migración documentada en supabase/migrations/006_rider_search_visual_identity.sql.

---

## v1.5.14 · build 51

Objetivo: corregir el encuadre de rutas, terminar el modo oscuro en estados visibles y hacer la cancelación de servicios más resistente.

Cambios:

- el mapa reajusta automáticamente origen, destino y geometría completa de la ruta;
- el encuadre reserva el espacio ocupado por el panel inferior para que ningún punto quede tapado;
- al pasar de “Confirma tu ruta” a “Elige tu viaje” el mapa se vuelve a centrar según la nueva altura del panel;
- “Revisar ruta” vuelve a encuadrar ambos puntos en la zona visible;
- resumen de distancia/tiempo y categoría seleccionada adaptados al modo oscuro;
- diálogo de cancelación adaptado completamente al modo oscuro;
- al confirmar una cancelación, la búsqueda desaparece de la UI de forma inmediata mientras el backend confirma;
- cancelaciones repetidas son idempotentes;
- si un conductor fue asignado justo mientras el pasajero cancelaba, se cancela también el viaje si todavía no comenzó;
- backend de viajes y delivery reforzado para evitar estados visualmente “pegados”.

---

## v1.5.13 · build 50

Objetivo: mostrar los vehículos disponibles también en el mapa principal del pasajero.

Cambios:

- los vehículos cercanos ya no dependen de que exista una solicitud abierta;
- el Home usa el origen seleccionado o la ubicación GPS actual para consultar conductores disponibles;
- al terminar de resolver el GPS se refresca inmediatamente el estado del mapa;
- radio visual de vehículos cercanos ampliado a 10 km;
- los marcadores siguen mostrando sólo conductores reales aprobados y en línea;
- los vehículos continúan diferenciando auto, moto y XL.

---

## v1.5.12 · build 49

Objetivo: acercar la experiencia de búsqueda de viaje al flujo de movilidad en tiempo real de la referencia visual y ampliar la selección de métodos de pago.

Cambios:

- selector de ubicación con modo oscuro completo, incluyendo buscador, panel inferior y campos;
- controles y tarjetas de Rider más compactos para aprovechar mejor pantallas móviles;
- búsqueda de conductores con radar animado;
- conteo real de conductores que visualizaron la solicitud;
- marcadores de vehículos cercanos en el mapa, diferenciando auto, moto y XL;
- posiciones de conductores expuestas al pasajero de forma aproximada y sin identidad;
- ofertas de conductor con tarjeta grande, aceptar/rechazar y expiración visual de 20 segundos;
- ofertas vencidas se invalidan también en backend;
- mensaje de cancelación de búsqueda más limpio cuando el estado ya cambió;
- métodos de pago declarativos: Efectivo, PagoRUT, Mercado Pago, Banco Santander, MACH y Tenpo;
- estos métodos sólo indican cómo pagará el pasajero y no ejecutan pagos online;
- backend actualizado para registrar los nuevos identificadores de pago;
- nueva tabla de visualizaciones de solicitudes y RPC seguros para búsqueda en tiempo real;
- migración documentada en supabase/migrations/004_rider_live_search_and_payment_labels.sql.

---

## v1.5.9 · build 46

Objetivo: separar el flujo de destino en tres etapas como la referencia de video: buscar destino, verificar ruta y recién después mostrar precios/opciones.

Cambios:

- al elegir destino desaparecen saludo, “¿A dónde vas?”, buscador, lugares guardados y recientes;
- nueva etapa “Confirma tu ruta” con origen y destino editables;
- origen y destino pueden corregirse antes de continuar;
- la etapa de verificación muestra distancia y tiempo, pero no precio;
- la cotización de tarifa se solicita después de confirmar la ruta;
- después de confirmar se muestra “Elige tu viaje” con categorías, precio, horario y pago;
- botón “Revisar ruta” permite volver a la verificación sin perder los puntos;
- editar origen o destino invalida automáticamente la confirmación anterior;
- tarjetas de origen/destino adaptadas al modo oscuro.

---

## v1.5.8 · build 45

Objetivo: replicar la interacción de selección de ubicación observada en la referencia de video.

Cambios:

- el pin deja de arrastrarse de forma independiente;
- el pin queda fijo en el centro mientras el usuario mueve el mapa;
- al comenzar el movimiento, el pin se eleva visualmente;
- al detenerse el mapa, el pin cae con rebote sobre el punto central;
- la coordenada seleccionada se toma del centro real del mapa;
- reverse geocoding se ejecuta sólo después de que el mapa se detiene;
- las respuestas de geocodificación antiguas ya no pueden sobrescribir la selección más reciente;
- el botón de confirmación queda deshabilitado mientras el mapa se mueve o se resuelve la dirección;
- tocar otro punto del mapa centra ese punto debajo del pin;
- el selector de ubicación usa OpenStreetMap con filtro local en modo oscuro, sin API key.

---

## v1.5.7 · build 44

Objetivo: corregir el mapa oscuro después del cambio de CARTO que empezó a exigir API key en sus basemaps.

Cambios:

- retirado CARTO del Home para evitar el mosaico “API KEY REQUIRED”;
- OpenStreetMap queda como proveedor base sin clave;
- en modo oscuro se aplica un filtro local a los mosaicos para conservar apariencia oscura;
- eliminada la atribución CARTO porque ya no se usa ese proveedor;
- corregida la clave de limpieza de caché web;
- actualización de versión web.

---

## v1.5.6 · build 43

Objetivo: separar la navegación fija Viaje/Delivery del panel deslizable y permitir que el contenido del Home suba completo antes de desplazarse internamente.

Cambios:

- barra inferior Viaje Express / Delivery movida fuera del panel y dejada fija;
- el panel principal conserva su posición base y ahora puede expandirse hasta el 92 % de la vista;
- el gesto hacia arriba prioriza expandir la pestaña antes de desplazar su contenido;
- Viajes recientes vuelve a mostrar hasta 4 accesos compactos;
- tarjetas de viajes recientes adaptadas a modo claro y oscuro;
- actualización de versión y clave de caché web.

---

## v1.5.5 · build 42

Objetivo: corregir el Home del pasajero según comparación directa con la referencia visual.

Cambios:

- calificación pendiente retirada del Home;
- Centro Express movido al menú;
- botones flotantes globales retirados;
- Viajes recientes simplificado;
- buscador principal más visible;
- panel base ajustado;
- modo oscuro real para el Home;
- mapa oscuro cuando el dispositivo usa tema oscuro;
- botones superiores adaptados;
- badge de versión reducido.

---

## v1.5.4 · build 41

Objetivo: compactar el inicio del pasajero y estabilizar su panel principal.

Cambios:

- panel base fijo al 56%;
- el panel ya no puede bajar por debajo de su posición principal;
- expansión sólo hacia arriba;
- menos padding vertical;
- saludo y título compactados;
- buscador más compacto;
- Casa y Trabajo reducidos;
- Viajes recientes compacto;
- selector Viaje Express / Delivery en una sola fila;
- toda la información principal visible sin arrastrar.

---

## v1.5.3 · build 40

Objetivo: simplificar el inicio de Express Rider usando la referencia visual enviada.

Cambios:

- mapa más limpio con solo menú y botón de centrar ubicación;
- se elimina el selector visible Pasajero/Conductor del encabezado;
- panel inicial centrado en “¿A dónde vas?”;
- buscador principal grande y único;
- origen oculto del inicio porque usa la ubicación actual por defecto;
- Casa y Trabajo como accesos directos;
- enlace “Ver todos” para lugares guardados;
- bloque de viajes recientes;
- selector simple Viaje Express / Delivery al pie del panel;
- categorías, pago, tarifa y horario aparecen únicamente después de elegir destino;
- navegación inferior global oculta mientras se está en Inicio para evitar duplicidad;
- Historial, Pagos y Perfil siguen disponibles desde el menú y recuperan navegación al abrirse.

---

## v1.5.2 · build 39

Objetivo: estabilizar el selector de ubicación y el panel principal del pasajero.

Cambios:

- el pin se renderiza siempre como marcador real del mapa;
- el área táctil de arrastre queda separada del marcador visual;
- destino inicia en la ubicación actual/origen aunque coincida;
- la validación de origen=destino ocurre únicamente al confirmar;
- tocar, buscar o arrastrar ya no dispara la advertencia antes de guardar;
- panel Viaje/Delivery con altura inicial fija;
- panel con posiciones de snap más estables y menos extremas.

---

## v1.5.1 · build 38

Objetivo: corregir el arrastre manual del pin de ubicación.

Cambios:

- pin separado del sistema de gestos del mapa;
- área táctil ampliada;
- arrastre real del pin;
- mapa bloqueado sólo mientras se arrastra el pin;
- actualización de dirección al soltar;
- feedback visual durante el movimiento;
- toque sobre mapa conservado como alternativa.

---

## v1.5.0 · build 37

Objetivo: mejorar funciones y experiencia de Express Rider y Express Conductor.

Cambios:

- cálculo de ruta con distancia y duración;
- tarifa sugerida desde las reglas configuradas;
- distancia/duración guardadas en solicitudes;
- Conductor ve distancia al origen, distancia total, ETA aproximada y pago;
- tarjetas de solicitud rediseñadas;
- calificación pendiente visible después de completar servicios;
- calificación con estrellas y comentario;
- historial Rider sin duplicados;
- filtros de historial y viajes programados;
- ganancias del conductor por período;
- total, promedio y desglose Viajes/Delivery;
- notificaciones con fecha/hora;
- marcar todas las notificaciones como leídas.

---

## v1.4.3 · build 36

Objetivo: pulido visual y responsive del Express Admin.

Cambios:

- tema visual exclusivo del Admin;
- inputs, botones, chips, menús y diálogos normalizados;
- transición a drawer en pantallas medianas para evitar headers apretados;
- app bar móvil más limpia;
- Conductores y Usuarios compactados;
- acciones de conductor agrupadas;
- Despacho responsive;
- Zonas y Tarifas con filas administrativas más limpias;
- headers con botones adaptables a móvil;
- App Builder responsive en 1, 2 o 3 columnas;
- aviso de actualización reducido y flotante;
- badge de versión menos invasivo.

---

## v1.4.2 · build 35

Objetivo: alinear visualmente Express Admin con la referencia mostrada en video.

Cambios:

- sidebar claro con grupos de navegación;
- tarjeta de empresa actual;
- selección activa en azul suave;
- header administrativo compacto;
- botón Nuevo viaje;
- accesos de actualización, bug, notificaciones, idioma y cuenta;
- Dashboard reorganizado con KPIs principales;
- Acciones rápidas;
- Estado del sistema;
- componentes visuales reutilizables;
- listas más compactas;
- búsqueda local en listas;
- filtros por estado;
- badges de estado;
- Configuración con pestañas horizontales;
- App Builder en tarjetas Android / iOS / Código Fuente;
- historial de builds visualmente renovado;
- responsive mantenido.

---

## v1.4.1 · build 34

Objetivo: corregir el acceso al Panel Administrador.

Cambios:

- ruta Admin estable mediante `?admin=1`;
- se mantiene compatibilidad con `#admin`;
- también se acepta `?mode=admin`;
- las cuentas con permiso administrativo muestran un botón `Panel administrador` dentro de la app;
- el acceso al Admin ya no depende únicamente de que el navegador conserve el fragmento de URL.

---

## v1.4.0 · build 33

Objetivo: convertir Express Admin en un centro de operaciones real inspirado funcionalmente en la arquitectura revisada de CabGo.

Cambios:

- nuevo Dashboard administrativo;
- KPIs de conductores online, búsquedas, viajes, delivery, cancelaciones, SOS y cobros;
- mapa operativo;
- actividad reciente;
- vistas reales de Viajes y Delivery;
- administración de Conductores y Usuarios;
- resolución de SOS;
- Zonas de operación;
- jerarquía de tarifas Global → Servicio → Zona+Servicio;
- tarifa base, km, minuto, mínimo, surge y comisión;
- Pagos/Billetera y resumen financiero;
- Reportes por período;
- configuración global de módulos y métodos de pago;
- dispatch broadcast, progressive y manual;
- despacho manual con validación de conductor disponible;
- auditoría de acciones sensibles;
- estructura segura del Build Center sin exponer tokens de GitHub.

---

## v1.3.7 · build 32

Objetivo: evitar rutas inválidas y mejorar interacción del mapa en pantallas pequeñas.

Cambios:

- el destino no puede ser igual al origen;
- se considera inválido un destino a menos de ~25 m del punto de recogida;
- la validación se hace tanto en el selector como antes de crear el servicio;
- si se intenta usar la misma ubicación, se muestra un mensaje claro y no se crea la solicitud;
- al abrir el selector de destino ya no se selecciona automáticamente el mismo punto del origen;
- el mapa se centra alrededor del origen para que el usuario elija otro destino;
- área de agarre del pin ampliada a 108 px;
- todo el entorno visible del pin responde al gesto de arrastre;
- si al arrastrar el pin termina sobre el origen, vuelve al punto anterior;
- panel inferior de Pasajero y Conductor limitado al 60 % de altura;
- nuevos puntos de snap: 23 %, 42 % y 60 %;
- se evita que el panel cubra controles superiores.

---

## Próxima release: v1.3.6 · build 31

Objetivo: mejorar selección de ubicación y eliminar el parpadeo de verificación inicial.

Cambios:

- pin de ubicación arrastrable;
- mientras se arrastra el pin, el mapa no se desplaza;
- tocar el mapa también cambia el punto;
- reverse geocoding al mover el pin;
- autocompletado de direcciones mientras se escribe;
- hasta 6 sugerencias;
- búsquedas sesgadas hacia la zona actual para mejorar resultados locales;
- seleccionar una sugerencia centra el mapa y actualiza la dirección;
- la misma experiencia se usa en origen y destino;
- verificación de servicio silenciosa durante los primeros 450 ms;
- solo se muestra “Verificando tu servicio…” cuando la consulta realmente tarda;
- refresh periódico mantiene el último estado válido y no vuelve a mostrar carga intermedia;
- cuenta de conductor de prueba aprobada directamente en backend para QA del flujo real.

---

## v1.3.5 · build 30

Objetivo: corregir cancelación, acelerar Inicio y hacer útil Mis servicios.

Cambios:

- agregado `ride_requests.updated_at`;
- trigger `touch_ride_request_updated_at`;
- corregido error:
  - `42703 column "updated_at" of relation "ride_requests" does not exist`;
- validación de `cancel_ride_request`;
- nuevo RPC `passenger_home_state()`;
- carga del estado del pasajero en una sola llamada;
- pantalla inicial “Verificando tu servicio…”;
- ocultar estados incorrectos antes de conocer la situación real;
- cierre/filtrado de solicitudes de viaje expiradas;
- ofertas pendientes de solicitudes expiradas pasan a declined;
- los conductores dejan de ver búsquedas vencidas;
- tarjetas de Mis servicios preparadas para abrir detalle;
- detalle de servicio:
  - estado;
  - origen;
  - destino;
  - tarifa;
  - método de pago;
  - categoría;
  - fecha;
  - programación;
  - conductor/repartidor;
  - vehículo;
  - rating.

---

## v1.3.4 · build 29

Objetivo: resolver actualizaciones web que detectaban una versión nueva pero seguían cargando JavaScript viejo.

Cambios:

- botón Actualizar ahora recibe versión de destino;
- cache-busting por URL;
- limpieza de caches;
- eliminación/desregistro de service workers anteriores;
- ejecutable Flutter Web con nombre único por versión;
- workflow deja de depender solo de `main.dart.js`;
- bootstrap versionado;
- `version.json` sigue siendo fuente de versión publicada.

---

## v1.3.3 · build 28

Objetivo: completar funciones alrededor de un servicio activo.

Cambios:

- tarjeta de servicio activo mejorada;
- persona asignada;
- vehículo;
- rating;
- Mapa;
- Chat;
- Llamar;
- cancelación con motivo;
- controles del conductor:
  - Ir al pasajero;
  - Llegué;
  - Iniciar viaje;
  - Completar;
- controles Delivery:
  - Paquete recogido;
  - Salir a entregar;
  - Marcar entregado;
- Viajes programados;
- `scheduled_for`;
- Billetera Express;
- wallet accounts;
- wallet transactions;
- settlement de pagos wallet;
- accesos directos a Lugares guardados;
- acceso directo a Seguridad/SOS.

---

## v1.3.2 · build 27

Objetivo: eliminar el parpadeo de “Buscando conductores…”.

Cambios:

- conservar último estado válido durante refresh;
- no sustituir temporalmente búsqueda real por estado vacío;
- misma idea aplicada a modo Conductor.

Después se mejoró todavía más con `passenger_home_state()` en build 30.

---

## v1.3.1 · build 26

Objetivo: pulir la experiencia map-first.

Cambios:

- botón ☰ convertido en menú real;
- accesos a Historial, Pagos y Perfil;
- menú separado para Conductor;
- cargas de Historial/Pagos con estructura visible;
- ruta vial por OSRM en vez de solo línea recta;
- fallback a línea directa si routing no responde.

---

## v1.3.0 · build 25

Objetivo: cambio mayor de experiencia visual.

Cambios:

- mapa como Inicio;
- panel inferior deslizable;
- experiencia Pasajero;
- experiencia Conductor;
- Viaje / Delivery;
- origen;
- destino;
- categorías:
  - Express;
  - Comfort;
  - XL;
  - Moto;
- tarifa propuesta;
- método de pago;
- lugares guardados;
- búsqueda de conductor;
- ofertas;
- solicitudes para conductor;
- online/offline;
- tracking.

---

## v1.2.9 · build 24

Objetivo: detector automático de actualización.

Cambios:

- `version.json`;
- polling de versión publicada;
- banner:
  - Actualización disponible;
  - número de versión;
  - Actualizar ahora;
- badge de versión actual permanece visible.

Posteriormente el mecanismo de recarga fue endurecido en v1.3.4.

---

## v1.2.8 · build 23

Objetivo: reparar carga de perfil autenticado.

Cambios:

- `ensure_my_profile`;
- autorreparación de perfil;
- pantalla de error útil;
- botón Reintentar;
- correcciones RLS;
- eliminación de recursión entre policies.

Error importante corregido alrededor de esta etapa:

`42P17 infinite recursion detected in policy for relation "delivery_requests"`

---

## Versiones anteriores

Antes de esta etapa existían:

- flujo Delivery original;
- login básico;
- previews separados;
- esquema inicial `profiles/orders`;
- primeras migraciones 001-003.

Esos archivos siguen presentes en parte por compatibilidad/historia, pero **no deben asumirse como representación de la experiencia actual**.

---

## Regla de changelog

Cuando una build cambie:

- arquitectura;
- backend;
- RLS;
- flujo principal;
- versión;
- deployment;
- pagos;
- seguridad;

agregar aquí un resumen breve y actualizar también `START_HERE_EXPRESS.md` si cambia la forma de continuar el proyecto.


## Promoción Android 1.5.91+135 · 2026-10-04

- Se inicia promoción manual de la Preview validada `1.5.91+135`.
- SHA fijado para Preview/Producción: `acb744e700babef87a608fa7b99570ee62b764ba`.
- El build de Producción debe usar exactamente ese SHA mediante `app_release_gate`.
- Google Auth debe permanecer habilitado en el build Android normal.

- Producción 1.5.91+135 en cola tras aprobar Preview normal con el mismo SHA.


## 1.5.92+137 · onboarding de conductor por país/ciudad

- Nuevo registro de conductor en 5 pasos: ubicación/servicios, perfil, vehículo, documentos y revisión.
- País sugerido por GPS + reverse geocoding; selección manual siempre disponible.
- Ciudad limitada a zonas Express activas del país.
- Servicios del conductor filtrados estrictamente por `zone_service_catalog`; Trinidad e Iquique no comparten servicios globales.
- Foto de perfil y hasta 4 fotos del vehículo desde cámara o galería.
- Documentos configurables por admin, con frente/reverso/selfie y almacenamiento privado.
- AdminExpress puede crear, editar, activar/desactivar y borrar requisitos por país o ciudad.
- Ficha del conductor permite abrir fotos/documentos mediante URLs firmadas temporales.
- Preparado para comparación selfie ↔ documento y liveness; proveedor actual: revisión manual.
- Seguridad: el conductor no puede autoaprobar documentos y solo puede referenciar archivos de su carpeta privada.
- Nueva base Preview requerida por dependencia nativa `image_picker`; versión `1.5.92+137`.

- 2026-10-05: Didit Live habilitado para onboarding de conductores en Producción (Bolivia). Trinidad usa identidad verificada por Didit y la selfie aprobada como foto de perfil; carné/licencia manuales de alcance país quedan desactivados para permitir requisitos por zona.

---

## 1.6.0+161 · hardening de arranque y QA Android

- Se invalida la promoción de +159 tras reproducir en dispositivo real `Express no pudo iniciar`.
- +160 queda como build genérico de diagnóstico y **no es promovible**.
- Preview y Producción comparten el mismo bootstrap resiliente de Supabase/auth.
- Firebase push y UI de llamadas pasan a ser servicios no críticos para el montaje inicial.
- Se agrega prueba de regresión para sesión/PKCE corruptos en SharedPreferences.
- El builder Android falla antes de compilar si `pubspec`, número de build y SHA solicitado no coinciden.
- El auditor compila y ejecuta un smoke del entrypoint real de Producción `com.express.usuario1`.
- QA amplía el viaje sintético hasta finalización y comprueba calificación pendiente en ambos roles.
- El release gate exige certificado QA exacto antes de permitir aprobación y Producción.
- Solo la release Preview Shorebird puede actualizar el Preview autoritativo; un `preview-android` genérico no puede reemplazarlo.

## 1.6.0+162 · candidato limpio tras auditoría de trazabilidad

- +161 publicó un APK, pero el tag de GitHub quedó apuntando a un commit distinto del SHA auditado porque `gh release create` no fijaba `--target`.
- +161 queda invalidado para promoción aunque su APK exista.
- El workflow normal y el recovery ahora fijan explícitamente el tag al SHA auditado.
- +162 es el primer candidato que combina bootstrap compartido, smoke de Producción, viaje QA completo, ratings bidireccionales y release gate con certificado QA.
