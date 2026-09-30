# EXPRESS — START HERE / HANDOFF DEL PROYECTO

> Documento de continuidad para desarrollo humano o con IA.
>
> **Leer este archivo antes de modificar código, Supabase, despliegues o versiones.**
>
> Última actualización documental: 2026-09-30.
>
> Historial reciente de builds: `docs/CHANGELOG_ACTIVE.md`
>
> Referencia funcional de producto: `docs/CABGO_REFERENCE.md`

---

## 1. Identidad del proyecto

**Producto:** Express  
**Objetivo:** aplicación Flutter de **Pasajero + Conductor + Delivery**, con backend Supabase. El panel administrativo web vive separado en `jorge2610g/Adminexpress`.

> **Fase UI actual:** la experiencia pública está temporalmente en modo **solo Viajes/Taxi**. Delivery se mantiene en backend/código para una reactivación posterior, pero no debe mostrarse como opción nueva al pasajero ni al conductor.

### Repositorio

- GitHub: `jorge2610g/Expressdelivery`
- Rama de trabajo actual: `main`
- Preview web / GitHub Pages:
  - `https://jorge2610g.github.io/Expressdelivery/`

### Supabase correcto

- **Project ref:** `zgpijrznvaskgcmauwxx`
- Este es el proyecto de Supabase que corresponde a Express.

> **IMPORTANTE:** en conversaciones anteriores existió acceso a otro proyecto de Supabase que NO correspondía a Express. No ejecutar migraciones ni cambios en otro project ref por accidente.

### Versión de código al escribir este documento

- Objetivo actual: **Express v1.5.31 · build 72**
- `pubspec.yaml`: `1.5.31+72`
- Entrada usada por GitHub Pages: `lib/web_preview.dart`

La versión puede haber avanzado cuando leas esto. Antes de trabajar, comprobar siempre:

1. `pubspec.yaml`
2. `lib/web_preview.dart`
3. último workflow de GitHub Actions
4. `version.json` del despliegue publicado

---

## 2. Visión del producto

Express debe funcionar como una app moderna de movilidad similar al flujo de las apps de transporte actuales, pero integrando **Viajes y Delivery** en la misma plataforma.

La referencia visual actual es una experiencia **map-first**:

- mapa como pantalla principal;
- panel inferior deslizable;
- selección de origen y destino;
- categorías de servicio;
- precio/oferta;
- búsqueda de conductor;
- ofertas;
- conductor asignado;
- seguimiento;
- chat/llamada;
- estados del servicio;
- cancelación;
- pagos;
- historial.

La aplicación comparte la misma infraestructura para pasajeros, conductores y repartidores.

### Decisiones de producto actuales

- No usar botones de demo en la experiencia pública.
- Las cuentas reales deben poder registrarse.
- El registro permite elegir **Pasajero** o **Conductor**.
- El backend mantiene `active_mode` y actualmente permite cambiar entre experiencia Pasajero y Conductor.
- Un conductor aprobado puede trabajar con Viajes y Delivery.
- El conductor debe pasar por aprobación administrativa.
- La UI debe ser limpia, profesional y basada en mapa.
- La versión visible debe permanecer en la app para saber qué build está cargada.
- Los cambios importantes deben salir con número de versión/build nuevo.
- El preview web sirve para iterar rápidamente antes de generar Android/iOS.

---

## 3. Estado funcional actual

### 3.1 Autenticación

Archivo principal:

- `lib/auth_entry.dart`

Implementado:

- inicio de sesión por email y contraseña;
- creación de cuenta;
- nombre;
- teléfono;
- tipo de cuenta Pasajero/Conductor;
- metadata `account_type` y `active_mode`;
- redirección de confirmación de email hacia GitHub Pages;
- recuperación del perfil si Auth existe pero falta su fila pública.

Funciones/backend relevantes:

- `handle_new_user`
- `ensure_my_profile`
- `is_account_active`

### 3.2 Shell de cuenta

Archivo:

- `lib/connected_shell.dart`

Responsabilidades:

- cargar el perfil autenticado;
- autorreparar perfil faltante;
- bloquear la experiencia si la cuenta está suspendida/bloqueada;
- abrir Centro Express;
- abrir configuración/perfil de conductor;
- mostrar notificaciones;
- cargar la experiencia conectada real.

### 3.3 Pasajero — Inicio map-first

Archivo principal:

- `lib/video_style_home.dart`

Implementado:

- ubicación GPS;
- mapa OpenStreetMap;
- selección de origen;
- selección de destino;
- pin arrastrable sin desplazar el mapa;
- tocar el mapa para mover el punto;
- reverse geocoding después de mover el pin;
- autocompletado de direcciones con sugerencias mientras se escribe;
- búsqueda sesgada hacia la zona actual para resultados locales;
- bloqueo de origen y destino iguales o demasiado cercanos;
- área táctil ampliada del pin para facilitar arrastre;
- paneles map-first limitados a una altura segura para no tapar controles;
- ruta por calles mediante OSRM;
- fallback a línea directa si el router no responde;
- Viaje / Delivery;
- categorías:
  - Express;
  - Comfort;
  - XL;
  - Moto;
- oferta de tarifa;
- métodos de pago declarativos (no procesados por Express):
  - Efectivo;
  - PagoRUT;
  - Mercado Pago;
  - Banco Santander;
  - MACH;
  - Tenpo;
- lugares guardados;
- búsqueda de conductores;
- ofertas de conductores;
- aceptación de oferta;
- servicio activo;
- información de conductor/repartidor;
- vehículo;
- rating;
- mapa;
- chat;
- llamada;
- cancelación con motivo;
- seguimiento;
- viajes programados.

### 3.4 Optimización del estado de Inicio

El Inicio del pasajero ya no debe montar varias pantallas incorrectas mientras consulta datos.

Backend:

- RPC `passenger_home_state()`

Objetivo:

- devolver en **una sola llamada**:
  - viaje abierto;
  - viaje activo;
  - delivery activo;
  - ofertas;
  - lugares guardados;
  - persona asignada;
  - perfil del conductor.

Mientras esa primera comprobación termina, la UI debe mostrar:

**“Verificando tu servicio…”**

y no mostrar primero el formulario para después cambiar a “Buscando conductor”.

### 3.5 Solicitudes expiradas

`ride_requests` utiliza `expires_at`.

Corrección aplicada:

- solicitudes vencidas no deben seguir apareciendo como `searching`;
- el backend las pasa a `cancelled`;
- ofertas pendientes asociadas se declinan;
- `availableRideRequests()` filtra solicitudes expiradas.

Esto corrigió búsquedas antiguas que permanecían visualmente activas.

### 3.6 Conductor

Archivos principales:

- `lib/video_style_home.dart`
- `lib/driver_setup.dart`
- `lib/services/express_service.dart`

Implementado:

- perfil de conductor;
- estado de aprobación;
- licencia;
- vehículo;
- ciudad;
- ubicación;
- online/offline;
- solicitudes cercanas;
- Viajes;
- Delivery;
- oferta/contraoferta de precio;
- ETA en minutos;
- aceptar Delivery;
- seguimiento;
- actualización de ubicación;
- controles de viaje:
  - Ir al pasajero;
  - Llegué;
  - Iniciar viaje;
  - Completar viaje;
- controles de Delivery:
  - Paquete recogido;
  - Salir a entregar;
  - Marcar entregado;
- chat;
- llamada;
- cancelación en estados permitidos.

### 3.7 Viajes programados

Implementado en backend y UI.

Campo:

- `ride_requests.scheduled_for`

Comportamiento actual:

- pasajero puede elegir Ahora o fecha/hora;
- se exige al menos ~15 minutos de anticipación en UI;
- un viaje futuro aparece como “Viaje programado”;
- el conductor no debe recibirlo como solicitud inmediata;
- `availableRideRequests()` lo muestra al acercarse aproximadamente a 30 minutos del horario.

**Pendiente:** mover toda la activación programada a lógica del servidor/cron, para que no dependa del cliente.

### 3.8 Delivery

Implementado:

- creación;
- recogida;
- entrega;
- tarifa propuesta;
- pago;
- búsqueda de repartidor;
- aceptación;
- estados;
- seguimiento;
- chat;
- llamada;
- cancelación.

Estados principales:

- `searching`
- `accepted`
- `picked_up`
- `in_transit`
- `delivered`
- `cancelled`

### 3.9 Viajes

Solicitud:

- `searching`
- `offers_received`
- `cancelled`

Viaje asignado:

- `driver_assigned`
- `driver_arriving`
- `driver_waiting`
- `in_progress`
- `completed`
- `cancelled`
- `emergency`

### 3.10 Mis servicios / Historial

Archivo:

- `lib/connected_experience.dart`

Incluye:

- solicitudes de viaje;
- viajes;
- delivery;
- acciones disponibles;
- mapa cuando corresponde;
- ofertas;
- cancelación.

Cambio reciente:

- cada tarjeta se puede tocar;
- abre un detalle de servicio con:
  - estado;
  - origen;
  - destino;
  - tarifa;
  - pago;
  - categoría;
  - fecha;
  - programación;
  - conductor/repartidor;
  - vehículo;
  - rating.

### 3.11 Chat

Backend:

- tabla `service_messages`
- función `notify_service_message`

UI:

- `ServiceChatPage` en `lib/connected_center.dart`

El chat está vinculado a viajes/delivery reales.

### 3.12 Notificaciones

Backend:

- tabla `notifications`

UI:

- Centro Express;
- contador de no leídas;
- eventos de viaje, delivery, chat, wallet, etc.

**IMPORTANTE:** esto es notificación interna de la app/backend.

**Push nativo real (FCM/APNs) todavía está pendiente.**

### 3.13 Seguridad / SOS

Backend:

- `emergency_events`
- `trusted_contacts`
- función `raise_emergency`

UI:

- acceso desde Perfil;
- acceso directo desde menú map-first.

Objetivo:

- registrar emergencia;
- mantener ubicación/contexto;
- contactos de confianza.

### 3.14 Billetera Express

Tablas:

- `wallet_accounts`
- `wallet_transactions`

Funciones:

- `ensure_wallet`
- `settle_wallet_payment`
- `wallet_demo_topup`

Implementado:

- saldo;
- movimientos;
- pagos;
- ganancias;
- historial de pagos.

Comportamiento:

- si un servicio usa `wallet` y hay saldo suficiente:
  - descuenta al pagador;
  - acredita al conductor/repartidor;
  - registra movimientos;
  - marca el pago como pagado;
  - genera notificaciones.

Si no hay saldo suficiente, el pago no debe inventarse como completado.

**Antes de producción:** eliminar/restringir `wallet_demo_topup` o sustituirlo por recarga real mediante proveedor de pagos.

### 3.15 Pagos

Backend:

- `payment_transactions`

Métodos actuales:

- cash;
- wallet;
- card.

**Efectivo:** registrado en flujo.  
**Wallet:** backend real básico.  
**Tarjeta:** todavía requiere integrar pasarela real.

---

## 4. Separación de Adminexpress

Desde 2026-09-30 el panel administrativo **ya no forma parte de este repositorio**.

Repositorio del administrador:

- GitHub: `jorge2610g/Adminexpress`
- Web: `https://jorge2610g.github.io/Adminexpress/`

### Regla de arquitectura

`Expressdelivery` debe contener únicamente la aplicación que usan:

- pasajeros;
- conductores;
- repartidores.

`Adminexpress` contiene:

- Dashboard;
- Viajes/Delivery administrativos;
- Conductores;
- Usuarios;
- Seguridad/SOS;
- Zonas;
- Tarifas;
- Pagos/Billetera;
- Reportes;
- Configuración;
- Despacho;
- Auditoría;
- App Builder;
- publicación de releases.

Ambos repositorios usan el mismo proyecto Supabase. Por eso los RPCs/tablas administrativos permanecen en el backend aunque el código UI Admin haya sido retirado de Express.

### Limpieza aplicada en Express

Se eliminaron definitivamente del árbol activo:

- `lib/admin_panel.dart`;
- `lib/admin_control_sections.dart`;
- antigua entrada `lib/main.dart`;
- prototipo antiguo de órdenes (`models/order_model.dart`, `services/order_service.dart`, etc.);
- previews antiguos de login, viaje y delivery.

Las únicas entradas de aplicación vigentes son:

- web: `lib/web_preview.dart`;
- Android: `lib/mobile_main.dart`.

No volver a introducir rutas `?admin=1`, `#admin` ni imports de Admin dentro de Express.

### Android / App Builder

El App Builder se controla desde Adminexpress y crea trabajos en `build_jobs`.

Los cambios normales de código no disparan builds Android. El trigger `push` fue retirado del workflow. La compilación solo ocurre cuando Adminexpress crea un trabajo Android en cola; el scheduler del workflow lo recoge después.

El workflow de Express:

`.github/workflows/build-android.yml`

realiza:

1. checkout del código;
2. instalación de Flutter;
3. creación/configuración Android;
4. firma persistente de producción;
5. compilación APK;
6. compilación AAB;
7. GitHub Artifact temporal;
8. GitHub Release permanente;
9. actualización del estado del build en Supabase.

La firma Android usa un keystore privado persistente. Sus contraseñas se almacenan cifradas en Supabase Vault. El archivo JKS no se guarda en Git.

### Corrección crítica de cancelación v1.5.20

El backend ya confirmaba correctamente `ride_requests.status = cancelled`, pero la UI podía seguir mostrando “Buscando conductores” porque un `FutureBuilder` conservaba datos de una Future anterior.

Corrección:

- `cachedData` pasa a ser la fuente visual de verdad;
- las respuestas de Future obsoletas no sustituyen el estado local nuevo;
- IDs de viajes/trips/delivery cancelados se conservan como tombstones locales durante la sesión;
- incluso si llega un snapshot antiguo, la UI elimina el servicio cancelado antes de renderizar;
- una trip vieja vinculada al `ride_request_id` cancelado también se oculta;
- solo si el backend confirma que la cancelación falló se elimina el tombstone y se restaura el estado anterior;
- al cancelar, el panel de búsqueda se desmonta y vuelve al estado principal.

La base LIVE fue verificada con solicitudes recientes: las cancelaciones sí llegaban a estado `cancelled`; el defecto observado era de resincronización visual.


## 5. App Builder / APK / AAB — pendiente

El usuario quiere construir Android desde el panel web.

Flujo objetivo:

`Admin Express → Build → backend seguro → GitHub Actions → Flutter Build → firma → APK/AAB → enlace de descarga`

### Requisitos antes de implementarlo

Actualmente el repo no contiene una plataforma Android/iOS completa como parte central del flujo de producción.

Pendiente:

1. generar/verificar carpetas nativas Android;
2. definir package/applicationId de producción;
3. configurar iconos/splash;
4. crear keystore de producción;
5. almacenar keystore/passwords como GitHub Secrets;
6. workflow Android;
7. `flutter build apk --release`;
8. `flutter build appbundle --release`;
9. guardar artifact o GitHub Release;
10. API segura para disparar workflow desde Admin;
11. historial de builds en Supabase;
12. mostrar progreso;
13. botones Descargar APK / Descargar AAB.

### Seguridad

**Nunca poner un GitHub token o una keystore dentro del Flutter Web.**

El disparo de builds debe hacerse mediante backend/Edge Function con credenciales protegidas.

---

## 6. Archivos clave

### Entrada / deployment

- `lib/web_preview.dart`
  - entrypoint actual de la web;
  - inicializa Supabase;
  - decide app normal/admin;
  - contiene número visible de versión;
  - monta detector de actualización.

- `web/index.html`
  - bootstrap;
  - limpieza de caché;
  - cache busting;
  - título web.

- `.github/workflows/deploy-web.yml`
  - build;
  - versionado del JS;
  - `version.json`;
  - GitHub Pages.

### UI conectada

- `lib/connected_shell.dart`
  - cuenta;
  - estados de cuenta;
  - Centro Express;
  - entrada a experiencia real.

- `lib/connected_experience.dart`
  - tabs principales;
  - Historial;
  - Pagos;
  - Billetera;
  - Perfil;
  - Mis servicios;
  - detalles.

- `lib/video_style_home.dart`
  - Inicio map-first;
  - Pasajero;
  - Conductor;
  - búsqueda;
  - ofertas;
  - panel inferior;
  - ruta;
  - cancelación;
  - acciones activas.

- `lib/driver_setup.dart`
  - configuración del conductor/vehículo.

- `lib/connected_center.dart`
  - Centro Express;
  - chat;
  - notificaciones y funciones asociadas.

- `lib/service_tracking.dart`
  - seguimiento de servicio.

- `lib/location_picker.dart`
  - selección de ubicaciones.

- `lib/location_service.dart`
  - GPS/geolocalización.

### Backend client

- `lib/services/express_service.dart`
  - interfaz principal Flutter ↔ Supabase.

### Actualizaciones

- `lib/app_update_banner.dart`
- `lib/platform_reload.dart`
- `lib/platform_reload_web.dart`
- `lib/platform_reload_stub.dart`

### Admin

- `lib/admin_panel.dart`

### Archivos preview/legacy

Existen archivos de prototipos anteriores:

- `lib/login_preview.dart`
- `lib/ride_flow_preview.dart`
- `lib/delivery_flow_preview.dart`
- `lib/express_experience_preview.dart`

No deben convertirse accidentalmente en el entrypoint de producción.

---

## 7. Supabase — inventario LIVE actual

### Tablas públicas actuales

- `admin_users`
- `app_settings`
- `delivery_requests`
- `delivery_status_history`
- `driver_offers`
- `driver_profiles`
- `driver_vehicles`
- `emergency_events`
- `notifications`
- `payment_transactions`
- `ratings`
- `ride_requests`
- `saved_addresses`
- `service_messages`
- `trip_status_history`
- `trips`
- `trusted_contacts`
- `users`
- `wallet_accounts`
- `wallet_transactions`

### Funciones públicas importantes

- `admin_driver_queue`
- `admin_set_account_status`
- `admin_set_driver_approval`
- `admin_stats`
- `admin_user_list`
- `advance_delivery`
- `advance_trip`
- `can_read_driver_profile`
- `can_read_user_profile`
- `cancel_delivery`
- `cancel_ride_request`
- `cancel_trip`
- `claim_delivery`
- `ensure_my_profile`
- `ensure_wallet`
- `handle_new_user`
- `is_account_active`
- `is_admin`
- `is_approved_online_driver`
- `is_ride_request_passenger`
- `notify_ride_offer`
- `notify_service_message`
- `passenger_home_state`
- `raise_emergency`
- `refresh_driver_rating`
- `ride_request_is_open`
- `select_ride_offer`
- `settle_wallet_payment`
- `touch_ride_request_updated_at`
- `wallet_demo_topup`

---

## 8. ADVERTENCIA CRÍTICA — migraciones del repo no representan todavía toda la base LIVE

En el repositorio solamente existen actualmente:

- `supabase/migrations/001_initial_delivery_schema.sql`
- `supabase/migrations/002_delivery_app_policies.sql`
- `supabase/migrations/003_optimize_order_rls.sql`

Sin embargo, la base LIVE de Express ya contiene muchas tablas, funciones, RLS y correcciones posteriores que fueron aplicadas directamente durante el desarrollo.

### Consecuencia

Si alguien crea un Supabase nuevo ejecutando solo `001-003`, **NO obtendrá el backend actual de Express**.

### Prioridad P0

Crear migraciones nuevas que reflejen fielmente el estado LIVE actual.

Recomendación:

1. exportar schema actual;
2. comparar con `001-003`;
3. crear migraciones `004+`;
4. incluir:
   - users;
   - driver_profiles;
   - driver_vehicles;
   - ride_requests;
   - driver_offers;
   - trips;
   - delivery;
   - chat;
   - notifications;
   - payments;
   - wallet;
   - safety;
   - admin;
   - app_settings;
   - RLS;
   - funciones;
   - triggers;
5. probar desde una base vacía.

**No inventar una migración manual incompleta.**

---

## 9. Seguridad / RLS — lecciones importantes

### Problema ya corregido: recursión infinita

Error visto:

`42P17 infinite recursion detected in policy for relation "delivery_requests"`

Causa:

- una política de `delivery_requests` consultaba `driver_profiles`;
- una política de `driver_profiles` volvía a consultar `delivery_requests`.

Solución:

- helpers `SECURITY DEFINER` para las comprobaciones cruzadas;
- evitar políticas que se llaman indirectamente entre sí.

Funciones relacionadas:

- `is_approved_online_driver`
- `can_read_driver_profile`
- `can_read_user_profile`
- `ride_request_is_open`
- `is_ride_request_passenger`

### Regla para futuras modificaciones RLS

Antes de crear una policy que consulte otra tabla:

1. revisar las policies de esa segunda tabla;
2. comprobar si regresan a la primera;
3. si existe riesgo de ciclo, usar una función segura `SECURITY DEFINER`;
4. limitar grants;
5. probar con rol `authenticated`, no solo como postgres/admin.

### No exponer secretos

- La publishable key de Supabase puede estar en cliente según arquitectura.
- **Nunca** poner service-role key en Flutter.
- **Nunca** poner GitHub PAT en Flutter.
- **Nunca** poner keystore/passwords dentro del repo.

---

## 10. Fallos importantes ya corregidos

### Perfil autenticado pero pantalla vacía

Síntoma:

- login correcto;
- solo aparecía “Cerrar sesión”.

Correcciones:

- `ensure_my_profile`;
- mejor manejo de error;
- botón Reintentar;
- reparación de RLS.

### Recursión RLS

Síntoma:

- `42P17 infinite recursion`.

Corregido con helpers de seguridad.

### Cancelar búsqueda fallaba

Síntoma:

`42703 column "updated_at" of relation "ride_requests" does not exist`

Corrección:

- se agregó `ride_requests.updated_at`;
- trigger `touch_ride_request_updated_at`;
- cancelación validada contra backend.

### “Buscando conductores” aparecía/se quitaba

Primera causa:

- varias consultas secuenciales;
- `FutureBuilder` mostraba estado vacío durante refresh.

Primera corrección:

- conservar último estado válido.

Optimización actual:

- RPC atómico `passenger_home_state()`.

### Solicitudes antiguas seguían buscando

Causa:

- `expires_at` vencido pero `status=searching`.

Corrección:

- limpiar/ignorar expiradas;
- ofertas pendientes pasan a declined;
- conductores no ven expiradas.

### Actualización web detectaba versión pero no cargaba código nuevo

Síntoma:

- banner “Actualización disponible”;
- botón Actualizar ahora;
- después seguía apareciendo el build anterior.

Causa:

- caché de Chrome / Flutter Web;
- `location.reload()` no era suficiente.

Corrección actual:

- ejecutable Flutter con nombre versionado;
- eliminar service worker en deployment;
- limpiar caches antiguos;
- URL de update con cache-busting;
- `version.json` de despliegue;
- bootstrap versionado.

---

## 11. Sistema de versiones y actualizaciones

El usuario necesita poder saber con certeza qué versión está viendo.

### Fuente visible

En `lib/web_preview.dart`:

- `expressPackageVersion`
- `expressWebVersion`

Badge visible abajo a la derecha.

### Detector

`lib/app_update_banner.dart`

Consulta periódicamente:

- `version.json?t=...`

Cuando el servidor publica una versión distinta muestra:

- Actualización disponible;
- versión;
- botón “Actualizar ahora”.

### Deployment marker

El workflow crea:

`build/web/version.json`

Ejemplo:

```json
{
  "package": "1.3.5+30",
  "version": "1.3.5",
  "build": "30",
  "display": "Express v1.3.5 · build 30",
  "commit": "...",
  "deployed_at": "..."
}
```

### JS versionado

El workflow crea una copia con nombre único, por ejemplo:

`main.1-3-5-30.dart.js`

y modifica `flutter_bootstrap.js` para apuntar a esa versión.

Objetivo: impedir que el navegador reutilice `main.dart.js` de una build anterior.

### Regla de versionado actual

Para una release significativa actualizar:

1. `pubspec.yaml`
2. `lib/web_preview.dart`
3. `web/index.html`

**Mejora pendiente:** automatizar esto para que `pubspec.yaml` sea la única fuente de versión.

---

## 12. GitHub Pages / CI

Workflow:

- `.github/workflows/deploy-web.yml`

Build exacta:

```bash
flutter build web \
  --release \
  --target lib/web_preview.dart \
  --base-href /Expressdelivery/
```

Luego:

1. versiona JS principal;
2. elimina service worker generado;
3. crea `version.json`;
4. sube artifact;
5. despliega GitHub Pages.

### Concurrencia

El workflow utiliza:

```yaml
concurrency:
  group: pages
  cancel-in-progress: true
```

Esto significa:

- varios commits rápidos pueden cancelar builds anteriores;
- esto es esperado;
- **solo importa la build del commit más reciente**.

### Regla para trabajar

No hacer 10 commits de “release” mientras una build final está en cola.

Mejor:

1. agrupar cambios;
2. probar;
3. subir;
4. hacer bump final de versión;
5. esperar el workflow más nuevo;
6. verificar que:
   - Build Flutter Web = success;
   - Version Flutter executable = success;
   - Write deployed version marker = success;
   - Deploy Pages = success.

No afirmar “ya está desplegado” antes de ese último success.

---

## 13. Desarrollo local

Instalar dependencias:

```bash
flutter pub get
```

Ejecutar la experiencia actual en Chrome:

```bash
flutter run -d chrome -t lib/web_preview.dart
```

Build web equivalente a producción:

```bash
flutter build web \
  --release \
  -t lib/web_preview.dart \
  --base-href /Expressdelivery/
```

### Nota

`lib/main.dart` no debe asumirse automáticamente como el entrypoint de la experiencia más reciente.

GitHub Pages compila explícitamente:

`lib/web_preview.dart`

---

## 14. Mapas y ubicación

Stack actual:

- `flutter_map`
- `latlong2`
- `geolocator`
- OpenStreetMap;
- OSRM público para rutas.

### Limitación

OSM/OSRM públicos son adecuados para desarrollo/pruebas, pero para una operación comercial a escala se debe evaluar proveedor con SLA, límites y condiciones de uso adecuados.

Pendiente:

- persistir distancia/ETA reales;
- recalcular ETA conductor-pasajero;
- geocodificación robusta;
- proveedor comercial si escala;
- zonas operativas.

---

## 15. Roadmap priorizado

### P0 — antes de considerar producción seria

- [ ] Sincronizar TODO el schema LIVE de Supabase a migraciones versionadas.
- [ ] QA completo de v1.3.5 build 30.
- [ ] Confirmar update web sin caché viejo en Android Chrome, desktop Chrome y modo instalado/PWA.
- [ ] Probar cancelación:
  - solicitud;
  - viaje;
  - delivery.
- [ ] Probar expiración automática.
- [ ] Probar `passenger_home_state()` con:
  - sin servicio;
  - búsqueda;
  - ofertas;
  - viaje activo;
  - delivery activo.
- [ ] Optimizar también Home del conductor a un RPC atómico.
- [ ] Sustituir polling de 8s por Realtime donde sea adecuado.
- [ ] Quitar/restringir `wallet_demo_topup`.
- [ ] Integrar pagos con tarjeta reales.
- [ ] Crear suite mínima de tests.
- [ ] Revisar toda la RLS con casos Pasajero/Conductor/Admin.

### P1 — experiencia completa de producto

- [ ] Panel Admin estilo referencia visual.
- [ ] Configuración general desde Admin.
- [ ] Zonas de cobertura.
- [ ] Tarifas por categoría.
- [ ] Tarifa mínima.
- [ ] Precio/km.
- [ ] Precio/min.
- [ ] Comisión.
- [ ] Precios dinámicos.
- [ ] Activar/desactivar Viajes/Delivery/módulos.
- [ ] Configurar métodos de pago.
- [ ] Branding/colores/logo/splash.
- [ ] Idiomas.
- [ ] Promociones.
- [ ] Referidos.
- [ ] Soporte/tickets.
- [ ] Métricas financieras.
- [ ] Emergencias en vivo.
- [ ] Mapa de conductores activos.
- [ ] Viajes programados administrables.
- [ ] Cron/worker para activar viajes programados.
- [ ] Rating UI completa.
- [ ] Push notifications reales.
- [ ] documentos/verificación de conductor.

### P1 — Build Center

- [ ] Android project.
- [ ] Firma release.
- [ ] APK.
- [ ] AAB.
- [ ] workflow Android.
- [ ] Edge Function/API segura para disparar workflow.
- [ ] historial builds.
- [ ] progreso build.
- [ ] enlaces de descarga.
- [ ] GitHub Release o almacenamiento dedicado.

### P2

- [ ] iOS project.
- [ ] firma Apple.
- [ ] TestFlight.
- [ ] publicación Play Store/App Store.
- [ ] observabilidad/errores.
- [ ] analytics.
- [ ] antifraude.
- [ ] escalado de mapas/routing.
- [ ] backups y recuperación.

---

## 16. Checklist de QA manual

### Auth

- [ ] registrar Pasajero;
- [ ] registrar Conductor;
- [ ] confirmar email;
- [ ] login;
- [ ] logout;
- [ ] perfil público creado;
- [ ] no aparece pantalla vacía.

### Pasajero

- [ ] GPS;
- [ ] mapa;
- [ ] origen;
- [ ] destino;
- [ ] ruta por calle;
- [ ] categoría;
- [ ] tarifa;
- [ ] pago;
- [ ] solicitar;
- [ ] “Verificando servicio” solo durante carga inicial;
- [ ] “Buscando conductores” estable;
- [ ] cancelar;
- [ ] oferta;
- [ ] aceptar;
- [ ] conductor;
- [ ] vehículo;
- [ ] chat;
- [ ] llamada;
- [ ] tracking;
- [ ] completar;
- [ ] historial;
- [ ] detalle de servicio.

### Conductor

- [ ] crear perfil;
- [ ] agregar vehículo;
- [ ] admin aprueba;
- [ ] online;
- [ ] recibe solicitudes no vencidas;
- [ ] oferta;
- [ ] pasajero acepta;
- [ ] Ir al pasajero;
- [ ] Llegué;
- [ ] Iniciar;
- [ ] Completar;
- [ ] Delivery;
- [ ] ganancias;
- [ ] wallet.

### Seguridad

- [ ] contacto de confianza;
- [ ] SOS;
- [ ] evento registrado;
- [ ] notificación.

### Admin

- [ ] solo admin accede;
- [ ] stats;
- [ ] lista conductores;
- [ ] aprobar/rechazar;
- [ ] usuarios;
- [ ] suspender/bloquear.

### Actualización

- [ ] versión vieja abierta;
- [ ] deploy nueva versión;
- [ ] aparece banner;
- [ ] banner muestra versión correcta;
- [ ] Actualizar ahora;
- [ ] badge cambia;
- [ ] no queda JS anterior en caché.

---

## 17. Reglas para una IA que continúe este proyecto

1. **Leer este archivo primero.**
2. Trabajar sobre `jorge2610g/Expressdelivery`.
3. Verificar que Supabase sea `zgpijrznvaskgcmauwxx`.
4. No tocar otro proyecto de Supabase.
5. No agregar botones “Demo” salvo petición explícita.
6. No reemplazar la experiencia real por archivos preview antiguos.
7. Mantener Pasajero + Conductor + Delivery.
8. Mantener el mapa como experiencia principal.
9. No eliminar el badge de versión.
10. No duplicar el badge de versión.
11. Para cambios de DB, revisar RLS antes de aplicar.
12. Evitar RLS recursiva.
13. No asumir que `001-003` refleja la base LIVE.
14. No exponer tokens o secrets en Flutter.
15. No decir que una versión está desplegada hasta comprobar GitHub Actions.
16. Debido a `cancel-in-progress`, mirar siempre el workflow del commit más nuevo.
17. Agrupar cambios antes del bump final de versión.
18. Conservar las funciones existentes mientras se rediseña UI.
19. Si una pantalla falla, mostrar el error útil; no dejar una pantalla blanca.
20. UI y mensajes en español.
21. Priorizar comportamiento móvil.
22. El usuario prefiere cambios visibles y poder probar cada build por web.
23. Cuando se agregue algo importante, documentarlo aquí.

---

## 18. Próximo punto recomendado al retomar

Al retomar desde este documento:

1. comprobar que **v1.3.5 build 30** o una versión posterior haya desplegado correctamente;
2. probar Cancelar búsqueda;
3. probar carga inicial del Inicio;
4. probar Mis servicios → detalle;
5. si todo está bien, continuar con:
   - Home conductor atómico/realtime;
   - Admin completo;
   - sincronización de migraciones LIVE;
   - Build Center APK/AAB.

---

## 19. Principio de continuidad

El objetivo no es rehacer Express en cada sesión.

Antes de proponer una solución nueva:

- revisar lo ya existente;
- conservar lo que funciona;
- corregir de forma incremental;
- mantener backend y UI sincronizados;
- dejar la siguiente versión claramente identificada;
- actualizar este documento cuando cambie la arquitectura.

Este archivo es el **punto de entrada para continuar el proyecto sin depender de la memoria de una conversación anterior**.
