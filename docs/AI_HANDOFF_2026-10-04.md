# Express — AI handoff operativo (2026-10-04)

## Actualización: Didit nativo candidato 1.5.93+138

El onboarding de conductor pasa de navegador externo al SDK Flutter nativo de Didit en Preview.

Reglas operativas:
- paquete: `didit_sdk_autodetection` (captura automática, sin NFC);
- Android mínimo: API 23;
- sesión siempre creada por `didit-identity`; nunca exponer API key ni workflow secreto en el APK;
- el SDK recibe un `session_token` efímero;
- webhook/endpoint de decisión siguen siendo la fuente autoritativa de aprobación;
- el regreso del SDK ejecuta reconciliación backend;
- cambio nativo => nueva base Preview obligatoria, no Shorebird patch;
- no promover Producción hasta certificar el mismo SHA.


> Documento autoritativo de continuidad para otra IA o desarrollador.
>
> Este archivo describe el estado real posterior a los cambios de 2026-10-04. Si contradice información histórica de otros documentos, usar este como referencia más reciente.

## 1. Resumen ejecutivo

Express es una app Flutter única con dos roles principales:

- Pasajero
- Conductor

Delivery existe como módulo/vertical dentro de la arquitectura, pero la marca global visible debe ser **Express**.

Backend compartido:

- Supabase project ref: `zgpijrznvaskgcmauwxx`

Panel administrativo separado:

- repo: `jorge2610g/Adminexpress`
- web de uso actual: `admin.expressviajes.online`

La app y el panel comparten Supabase, pero NO comparten frontend.

---

## 2. Estado actual de código y Producción

### Producción Android actualmente generada

- versión: **1.5.87+131**
- SHA aprobado: `45c2aff26cd27229e445461d2f129023bf6f60df`
- package: `com.express.usuario1`
- tag GitHub Release: `android-v1.5.87-build131`
- firma: `production`
- APK y AAB ya generados correctamente

Este SHA fue aprobado desde Preview y luego usado exactamente para Producción.

### Preview Shorebird

- versión base: **1.5.87+131**
- package: `com.express.usuario.preview`
- tag: `preview-shorebird-v1.5.87-build131`

Esta versión fue una base Shorebird nueva, por lo que requirió reinstalar la APK Preview una vez. Los cambios Dart compatibles posteriores pueden salir como patch.

### IMPORTANTE: main va por delante de la APK de Producción

Después del release 1.5.87+131 se hicieron cambios de QA/backend y panel.

Eso significa:

- `main` actual NO equivale exactamente al binario 1.5.87+131
- los cambios recientes del laboratorio QA no requieren reemplazar la APK, porque viven principalmente en Edge Function/Admin
- si se modifica código Dart de la app y se quiere llevar a Producción, debe crearse un nuevo Preview/versionado y repetir el gate

---

## 3. Estructura activa

Entradas:

- Producción Android: `lib/mobile_main.dart`
- Preview Android: `lib/preview_main.dart`
- Web: `lib/web_preview.dart`

Servicios/backend client:

- `lib/services/express_service.dart`

Pantallas principales:

- `lib/connected_shell.dart`
- `lib/connected_experience.dart`
- `lib/video_style_home.dart`
- `lib/express_account_pages.dart`
- `lib/driver_setup.dart`
- `lib/phone_verification_page.dart`
- `lib/phone_utils.dart`
- `lib/express_branding.dart`

Backend:

- `supabase/migrations/`
- `supabase/functions/`

QA:

- `.github/workflows/`
- `.github/scripts/`
- `.maestro/`

---

## 4. Branding actual

### Nombre

Marca general:

**Express**

No volver a mostrar **Express Delivery** como nombre principal de la app.

“Delivery” puede aparecer únicamente cuando identifica el servicio/módulo específico de entregas.

### Logo oficial

El logo oficial es el símbolo azul/blanco usado en splash y branding actual.

Implementación:

- asset protegido/restaurado por CI
- fuente: `assets/branding/express_app_icon_512.b64`
- widget centralizado: `ExpressOfficialLogo` en `lib/express_branding.dart`

Se reemplazaron íconos genéricos de rayo en:
- autenticación
- menú
- cabeceras
- branding conectado

No reemplazar este logo por variantes antiguas.

### Splash

Debe mostrar:

- logo oficial
- texto: **Express**
- lema: puede permanecer según diseño actual

No debe decir “Express Delivery” como título global.

---

## 5. Países, teléfonos y monedas

### Chile

- prefijo: `+56`
- moneda: `CLP`
- formato: sin decimales
- ejemplo: `$ 1.583`

### Bolivia

- prefijo: `+591`
- moneda: `BOB`
- entero: `Bs 25`
- fracción: `Bs 25.60`

Helpers de teléfono:

- `lib/phone_utils.dart`

El código normaliza E.164 y puede inferir país desde prefijo.

---

## 6. Verificación de teléfono por SMS

### Objetivo

El flujo OTP ya existe, pero la exigencia de SMS debe controlarse desde Admin.

### Switches

Dos switches independientes:

- Verificación SMS Pasajeros
- Verificación SMS Conductores

Campos:

- `app_settings.sms_verification_passenger_enabled`
- `app_settings.sms_verification_driver_enabled`

Estado esperado de Producción:

- pasajeros: OFF
- conductores: OFF

Preview también debe permanecer OFF salvo activación explícita.

### OFF

Cuando está apagado:

- no enviar SMS
- no bloquear pasajero
- no bloquear conductor
- no exigir OTP
- perfil puede indicar que la verificación SMS está desactivada

### ON

Pasajero:
- debe verificar antes de crear viaje

Conductor:
- debe verificar antes de ponerse online
- debe verificar antes de enviar oferta

Cuentas existentes:
- si no tienen `phone_verified_at`, reciben flujo de verificar/cambiar teléfono

### Backend

Migraciones:

- `094_zone_ride_payments_phone_verification.sql`
- `095_sms_verification_admin_switches.sql`

Ambas ya fueron aplicadas al Supabase de Express.

RPC/funciones relevantes:

- `phone_verification_enabled`
- `admin_phone_verification_settings_update`

Proveedor SMS/Twilio:
- no asumir que está configurado
- activar switches solo cuando el proveedor real esté listo

---

## 7. Pagos de viajes

Regla de negocio consolidada:

### Chile

Viajes:
- Efectivo

### Bolivia

Viajes:
- Efectivo
- QR del conductor

El QR es del conductor. El dinero del viaje va directo al conductor.

No usar:
- QR administrativo
- Mercado Pago administrativo
- VeriPagos administrativo

para cobrar viajes normales.

### Mercado Pago

Reservado para:
- suscripciones
- recargas

No usar para tarifa ordinaria del viaje.

### Backend

Migración 094:
- catálogo de métodos
- configuración por zona
- validación backend
- `driver_qr`
- preferencia pasajero
- métodos aceptados por conductor

RPCs:
- `my_ride_payment_methods`
- `set_my_preferred_ride_payment_method`
- `set_my_driver_payment_methods`
- `available_ride_requests_for_driver_v3`

El filtro de pago no debe existir solo en UI; backend también lo valida.

---

## 8. Servicios y tipo de vehículo

Relación actual importante:

- servicio `economy` = Auto / `car`
- servicio `motorcycle` = Moto / `motorcycle`

La app pasajero muestra marcadores filtrados por tipo de vehículo en Producción.

RPC:
- `nearby_online_driver_markers`

El conductor también filtra solicitudes por vehículo activo en cliente.

Función local:
- `_rideMatchesVehicle` en `connected_experience.dart`

Si un conductor Auto ve 0 mientras Admin muestra solicitudes:
- comprobar si esas solicitudes son `motorcycle`
- esto fue exactamente un fallo encontrado el 2026-10-04

---

## 9. Preview y Producción

### Runtime channel

Valores válidos:

- `preview`
- `production`

Las entidades sensibles usan `channel`.

### Regla de aislamiento

Preview y Producción comparten infraestructura, pero no deben compartir datos operativos.

Backend debe impedir:

- cuenta QA escribiendo Producción
- cuenta real escribiendo Preview

No eliminar los triggers/guardas por comodidad.

Mensaje visto durante una regresión QA:

`Una cuenta QA/Preview no puede crear datos de Producción`

Ese error era correcto; el bug estaba en el laboratorio, que omitía `channel`.

---

## 10. Laboratorio de carga QA

Edge Function:

`supabase/functions/express-load-lab/index.ts`

### Estado actual

Corregido el 2026-10-04 para:

- Preview -> `channel=preview`
- Producción -> `channel=production`
- cleanup aislado por scope
- Iquique -> CLP
- Trinidad -> BOB
- errores backend legibles
- push LOADTEST suprimido
- soporte Auto/Moto/Mixto

### Parámetro

`service_mode`:

- `mixed`
- `car`
- `motorcycle`

Default:

`mixed`

### Mixto

Distribuye conductores sintéticos entre:

- `car`
- `motorcycle`

y solicitudes entre:

- `economy`
- `motorcycle`

### Estado del escenario reparado manualmente

El escenario de Producción Iquique que originalmente tenía:
- 100 motos
- 100 solicitudes motorcycle

fue convertido a:
- 50 autos
- 50 motos
- 50 solicitudes economy
- 50 solicitudes motorcycle

También se renovó la expiración de las solicitudes durante la prueba.

Esto fue una corrección de datos QA, no un cambio de APK.

### Versión Edge Function

Última versión desplegada conocida:

- `express-load-lab` v12

---

## 11. Pasajero — marcadores del mapa

En `video_style_home.dart`:

- determina categoría efectiva
- busca `vehicle_type` del servicio
- Producción filtra estrictamente por tipo
- Preview puede usar fallback más tolerante para validar el flujo

Por eso en Producción:

- Auto muestra Auto
- Moto muestra Moto

No cambiar esto para mostrar vehículos incompatibles.

La captura validada el 2026-10-04 mostró correctamente varios autos sintéticos en Iquique después de corregir el escenario.

---

## 12. Conductor — solicitudes

Flujo principal:

`ExpressService.availableRideRequests()`

Primero intenta:

`available_ride_requests_for_driver_v3(channel)`

Fallback:
- v2

Backend filtra:
- cuenta activa
- conductor aprobado/online
- zona
- suscripción/dispatch
- radio
- servicio visible
- estado
- expiración
- scope
- channel
- pago aceptado

Cliente filtra adicionalmente por vehículo activo.

No eliminar filtros backend para “hacer aparecer” solicitudes.

---

## Regla permanente de identidad de release (2026-10-05)

Incidente que no debe repetirse: la cola llegó a procesar builds antiguos y QA pudo arrancar antes de resolver la Preview actual.

Protecciones obligatorias:

- `android-build-worker` reclama el build más nuevo, no el más antiguo;
- pendientes anteriores del mismo tipo se cancelan como reemplazados;
- `app_release_gate` es monotónico por `build_number`: un Preview viejo que termina tarde no puede convertirse en el actual;
- QA consulta primero el gate y prueba el SHA exacto de la Preview vigente;
- si `main` declara otra versión/build, QA bloquea hasta que exista esa Preview;
- si hay cambios sensibles de app después del SHA Preview sin una nueva Preview, QA bloquea;
- solo la Preview vigente puede aprobarse;
- Producción debe igualar Preview en versión + build + SHA;
- el worker vuelve a validar esa identidad al reclamar el job de Producción y otra vez antes de marcarlo listo/publicarlo.

No aprobar ni publicar Producción basándose únicamente en que un workflow está verde.

## 13. Release gate Android

Tabla:

`app_release_gate`

RPCs relevantes:
- `admin_approve_preview_build`
- `admin_create_build_job`

Regla:

Una Producción `apk+aab` debe usar exactamente:
- build Preview aprobado
- mismo commit SHA

El gate debe bloquear cualquier intento de usar otro SHA.

### build_jobs

Tipos:

Preview:
- `preview-apk+aab`

Producción:
- `apk+aab`

Workflow:

`.github/workflows/build-android.yml`

El workflow:
1. toma job en cola
2. checkout del SHA solicitado
3. restaura branding
4. configura Android
5. recupera firma segura
6. compila APK
7. compila AAB
8. publica GitHub Release
9. actualiza URLs/estado

Nunca asumir que un workflow verde generó APK. Revisar si realmente tomó un `build_job`; algunos pushes ejecutan el workflow y omiten pasos de build si no hay job en cola.

---

## 14. Firma Android

No regenerar.

Producción usa identidad persistente.

Secrets/keystore no deben vivir en Git.

Si Google Play solicita continuidad de firma, usar la firma ya configurada.

Package de Producción:

`com.express.usuario1`

---

## 15. QA automático

Workflow:

`Express QA Auditor`

### Cómo interpretar

Un run rojo puede ser:

- fallo producto
- infraestructura QA
- autenticación Maestro
- emulador
- credencial Visual AI
- assertion de texto desactualizada

Siempre mirar el verdict.

### Último estado conocido

Run posterior a las correcciones mixtas:
- build APK QA: success
- app process alive: true
- Android fatal evidence: 0
- new confirmed product failures: 0
- device verdict: `qa_inconclusive`
- backend: sin nuevos fallos confirmados

Problemas del harness observados:
- assertion de login no encontró “Correo electrónico”
- authenticated passenger smoke no encontró texto esperado
- driver smoke no encontró “Ganancias”
- Visual AI indicó credencial Maestro Cloud no disponible
- backend snapshot/gate pudo quedar warning/infrastructure

Regla:

No marcar como fallo de producto sin evidencia correlacionada.
Tampoco cambiar el gate para ignorar infraestructura obligatoria. Arreglar el harness.

---

## 16. Branding y versión visible

Cuando cambie código de app:
- incrementar versión/build
- no reutilizar build number publicado

Última versión Android de producto:
- 1.5.87+131

Cambios backend/admin posteriores no obligan automáticamente a subir versión Android.

---

## 17. Backend compartido con Adminexpress

No borrar RPCs administrativos desde Expressdelivery porque “no se usan en app”.

Adminexpress los usa.

Ejemplos:
- configuración
- builds
- zonas
- QA
- pagos
- conductor
- seguridad
- releases

---

## 18. Flujo recomendado para otra IA

### Cambio UI app

1. leer AGENTS + handoff
2. branch
3. editar
4. `flutter analyze`
5. build web/smoke
6. Preview
7. QA
8. aprobación
9. mismo SHA a Producción

### Cambio backend solamente

1. migración/Edge Function en repo
2. probar transacción reversible si es SQL
3. aplicar migration/deploy
4. validar queries/RPC
5. decidir si app necesita rebuild
6. documentar

### Cambio Admin

Hacerlo en `Adminexpress`, no aquí.

---

## 19. Checklist antes de tocar Producción

- [ ] Supabase ref correcto
- [ ] channel correcto
- [ ] no secretos en Git
- [ ] branding oficial
- [ ] moneda por zona
- [ ] método de pago por zona
- [ ] SMS no activado accidentalmente
- [ ] Preview probado
- [ ] SHA aprobado
- [ ] Producción usa mismo SHA
- [ ] firma production
- [ ] package `com.express.usuario1`
- [ ] APK y AAB disponibles
- [ ] QA verdict revisado, no solo color del workflow
- [ ] documentación actualizada

---

## 20. Decisiones que no se deben revertir sin autorización

- marca global = Express
- Admin separado
- Preview/Producción aislados
- Chile = CLP
- Bolivia = BOB
- Chile viajes = efectivo
- Bolivia viajes = efectivo + QR conductor
- Mercado Pago administrativo no cobra viajes
- SMS por rol controlado desde Admin y OFF por defecto
- release gate exact SHA
- firma Android persistente
- Auto/Moto filtrados correctamente
- QA sintético sin push real
- laboratorio QA con selector Auto/Moto/Mixto

---

## 21. Documentos relacionados

- `AGENTS.md`
- `docs/START_HERE_EXPRESS.md`
- `docs/QA_AUTOMATION.md`
- `docs/SAFE_IMPLEMENTATION_ROADMAP.md`
- `docs/CHANGELOG_ACTIVE.md`
- `docs/GOOGLE_PLAY_SUBMISSION.md`

Panel:
- repo `jorge2610g/Adminexpress`
- `AGENTS.md`
- `docs/AI_HANDOFF_2026-10-04.md`


## 22. Corrección de lectura QA por entorno (2026-10-04)

Se detectó que el panel podía mostrar el mismo escenario de carga al alternar **Prueba / Producción**.

Causa:
- el RPC legado `admin_audit_load_snapshot()` devolvía simplemente el último run activo global;
- no recibía `scope` ni ciudad;
- por eso una vista Producción podía pintar un run sandbox y viceversa.

Corrección:
- migración `096_admin_qa_scope_snapshot.sql`;
- nuevo RPC `admin_audit_load_snapshot_v2(p_scope, p_city_key)`;
- filtra por `metrics.scope_mode` y `metrics.city_key`, con fallback de etiquetas históricas;
- devuelve vacío si el entorno/ciudad seleccionado no tiene run activo;
- el RPC legado se conserva por compatibilidad, pero Adminexpress nuevo debe usar v2.

Regla:
- cambiar de Prueba a Producción NO debe borrar datos automáticamente;
- cada entorno conserva su propio escenario;
- la UI muestra únicamente el escenario del entorno seleccionado;
- limpiar actúa sobre el scope elegido.


---

## 23. Aislamiento runtime Pasajero / Conductor (candidato 1.5.88+132)

Corrección preparada el 2026-10-04:

- migración: `097_driver_mode_runtime_isolation.sql`;
- una cuenta que abandona modo Conductor queda `offline` automáticamente;
- no se permite abandonar modo Conductor durante un viaje/delivery activo;
- `online` / `busy` requieren cuenta activa y `active_mode=driver`;
- el push de nuevas solicitudes filtra también por `active_mode=driver`;
- el Home del conductor reactiva seguimiento GPS cuando existe un servicio activo, incluso después de reconstruir/reabrir la pantalla;
- al quedar offline, el stream GPS se cancela;
- el shell Conductor conserva su limpieza de timers, streams y canales Realtime al desmontarse.

Estado de release:
- candidato de código: **1.5.88+132**;
- Producción Android vigente continúa en **1.5.87+131** hasta aprobar Preview;
- no generar Producción desde este cambio sin pasar el gate Preview → QA → aprobación → mismo SHA.


---

## 24. Reducción de consumo Supabase/logs (candidato 1.5.89+133)

Diagnóstico del 2026-10-04:
- el mayor volumen reciente provenía de `edge_logs`;
- dos clientes Android concentraban la mayoría de requests;
- endpoints repetidos: `driver_profiles`, `passenger_live_offer_state_v2`, `pending_rating_service`, `my_driver_priority_summary`, `cleanup_expired_ride_requests`, `my_viewed_ride_request_ids`, listas de viajes/deliveries;
- no se encontró en el repo un proceso que consulte programáticamente el Logs API de Supabase; el consumo de Log Query debe mantenerse bajo evitando consultas amplias/repetidas de Studio/MCP.

Correcciones:
- pasajero: polling de respaldo menos agresivo y live-offer solo con solicitud abierta;
- conductor: polling de respaldo 12 s, viewed IDs una vez, prioridad 1 min, rating 30 s;
- ubicación: UI local conserva cada punto GPS, backend recibe ~3 s durante servicio activo y ~10 s online sin servicio;
- eliminado `cleanup_expired_ride_requests` del camino caliente de lectura;
- actualización GPS ya no hace una lectura previa redundante de `driver_profiles`.

Release:
- candidato: **1.5.89+133**;
- Producción Android permanece **1.5.87+131** hasta Preview/QA/aprobación;
- no publicar APK/AAB de Producción automáticamente.


---

## 25. Cuenta única Pasajero/Conductor (candidato 1.5.90+134)

Modelo definitivo:
- un correo = una identidad de Supabase Auth = un `public.users.id`;
- Pasajero es la experiencia inicial;
- Conductor se habilita sobre la misma identidad mediante `driver_profiles.id = users.id`;
- no crear una segunda cuenta ni pedir otro correo/contraseña;
- `active_mode` es estado operativo compartido de la cuenta, no un tipo de identidad.

Cambios app:
- registro elimina selector Cliente/Conductor;
- nuevas cuentas envían metadata inicial `passenger`;
- desde perfil: Conducir con Express / Continuar registro / Cambiar a Conductor;
- si faltan datos o vehículo, abre DriverSetup;
- si está pendiente, permanece como Pasajero;
- solo perfiles aprobados/completos pasan a modo Conductor;
- `users.active_mode` se escucha por Realtime y reconstruye el shell si otra sesión cambia el modo.

Cambios backend:
- migración `098_unified_account_role_reputation.sql`;
- agrega `ratings.rated_role = passenger|driver` derivado por trigger desde el servicio;
- backfill completo: 25 driver / 25 passenger / 0 sin clasificar;
- `my_rating_summary()` usa el rol activo;
- `refresh_driver_rating` y prioridad usan solo `rated_role='driver'`;
- ranking de pasajeros usa solo `rated_role='passenger'`;
- Admin driver/user detail separan reputación por rol;
- `public.users` agregado a `supabase_realtime`;
- funciones nuevas de rating no son ejecutables por `anon`.

Compatibilidad:
- cuentas y conductores existentes conservan IDs y datos;
- no se duplican usuarios;
- el backend histórico de alta se mantiene compatible con clientes antiguos durante la transición; el nuevo cliente ya no ofrece alta directa como Conductor;
- Producción Android sigue protegida: no publicar APK/AAB automáticamente.


---

## 26. Google Auth Preview (1.5.91+135)

Hallazgo:
- el botón `Continuar con Google` existía en código y en builds previos, pero se ocultaba por `EXPRESS_GOOGLE_AUTH_ENABLED=false`;
- el workflow de Preview intentó parchear `1.5.90+134` y Shorebird respondió `Release not found`, por lo que el dispositivo siguió con UI antigua.

Corrección:
- Google Auth habilitado en Preview y Web;
- fallback de futuros builds Android habilitado;
- nueva base Preview 1.5.91+135 para que Shorebird pueda crear release y luego recibir patches;
- Google/Supabase configurados con callback de `zgpijrznvaskgcmauwxx`;
- Producción Android sigue sujeta al gate manual.


---

## 27. Páginas legales bajo expressviajes.online

GitHub Pages continúa siendo el hosting, pero el dominio público configurado para Expressdelivery es `https://expressviajes.online/`.

URLs canónicas:
- Privacidad: `https://expressviajes.online/privacidad/`
- Términos: `https://expressviajes.online/terminos/`
- Eliminación: `https://expressviajes.online/eliminar-cuenta/`

Compatibilidad:
- se mantienen las rutas históricas `/privacy.html`, `/terms.html` y `/delete-account.html`;
- la app usa las rutas canónicas nuevas;
- no modificar DNS para este cambio;
- el callback OAuth web antiguo de GitHub se conserva hasta confirmar que `https://expressviajes.online/` esté agregado a Redirect URLs en Supabase.


## 27. Driver onboarding multi-paso · 1.5.92+137

Implementación en `feature/driver-onboarding-documents`.

Backend aplicado:
- migraciones `099_driver_onboarding_documents.sql` y `100_driver_onboarding_security_hardening.sql`;
- bucket privado `driver-onboarding`;
- requisitos de documentos administrables por país/ciudad;
- preferencias de servicios por zona;
- RPCs `driver_onboarding_catalog`, `my_driver_onboarding_state`, `submit_driver_onboarding`;
- defaults BO/CL para identidad y licencia;
- el conductor no puede modificar estado de verificación directamente.

App:
- `lib/driver_setup.dart` ahora es wizard de 5 pasos;
- GPS + reverse geocoding para sugerir país y zona;
- servicios estrictamente locales;
- cámara/galería con `image_picker`;
- foto de perfil, fotos de vehículo y documentos privados.

AdminExpress:
- panel de requisitos integrado en Verificación de identidad;
- CRUD de documentos por país/ciudad;
- apertura de fotos/documentos con URL firmada.

La comparación facial automática NO está conectada todavía. El esquema queda listo; provider sigue `manual` hasta configurar un proveedor de KYC/face-match/liveness.

Por incluir plugin nativo, usar nueva base Shorebird Preview `1.5.92+137`, no patch sobre 1.5.91+135.
