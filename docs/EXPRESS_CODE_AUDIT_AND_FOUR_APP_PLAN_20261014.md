# Plan histórico de cuatro apps — sustituido el 2026-10-24

La dirección de producto vigente coloca el reparto comercial en la app Express Principal y mantiene una app separada para comercios. La tabla y las tareas de cuatro apps de abajo ya no son instrucciones de implementación. Ver [`EXPRESS_DELIVERY_PRODUCT_DECISIONS_20261024.md`](EXPRESS_DELIVERY_PRODUCT_DECISIONS_20261024.md).

# EXPRESS — Auditoría de código, decisiones, retiradas y trabajo pendiente
**Corte de referencia:** 2026-10-14 (Chile). **Documento de continuidad vivo, NO certificado E2E.**
**Repositorio:** `jorge2610g/Expressdelivery`; base inspeccionada: `main` `f92bc2b73d1b1b0da642b813cc0f8e5d50174379`.
**Otros repos:** `jorge2610g/Adminexpress`, `jorge2610g/Express_Restaurante`, `jorge2610g/Express_Repartidor`.
**Backend compartido:** Supabase `zgpijrznvaskgcmauwxx`. **Producción web:** `https://expressviajes.online/`; **Admin:** `https://admin.expressviajes.online/`.

> **Cómo leer el estado:** FUSIONADO significa que el código está en `main`, NO prueba funcional física, publicación Play o activación comercial. QA CI significa pruebas automatizadas, NO audio/GPS/push E2E. PLANEADO significa requisito, NO implementación. La documentación histórica contiene versiones y planes superados; este archivo es la referencia temporal para la arquitectura de cuatro aplicaciones.

## 1. Decisión funcional DEFINITIVA del propietario

Una misma **app Express Principal** mantiene estos **cinco recorridos** y una sola identidad para pasajero/conductor:

| N.° | Experiencia | Ubicación definitiva |
| --- | --- | --- |
| 1 | Cliente solicita Taxi | Express Principal |
| 2 | Cliente solicita Envíos / paquetería entre personas | Express Principal |
| 3 | Cliente explora restaurantes/tiendas, compra Delivery, paga y sigue pedidos | Express Principal |
| 4 | Conductor recibe/realiza viajes Taxi | Express Principal |
| 5 | Conductor recibe/realiza Envíos de personas | Express Principal |

**Tres aplicaciones adicionales**, conectadas con Supabase pero con frontends, identidad operativa/push y release independientes:

- **Express Restaurante / Comercio:** pedidos, catálogo, menú/productos, extras, horarios, promociones, inventario cuando aplique, cobros/liquidaciones, perfil, notificaciones. Web responsiva y aplicación Android según diseño a validar.
- **Express Repartidor:** únicamente ofertas y entregas de **pedidos comerciales** de restaurantes, supermercados y tiendas. **NO Taxi; NO Envíos/parcel entre personas.**
- **Express Admin:** administración global, comercios, conductores, repartidores, zonas, pagos, logística, cupones, Plus, demos, informes, permisos y releases. Ya tiene repositorio propio; NO recrear segundo panel.

**No confundir** `delivery_requests` (tabla legacy que también representa paquetes) con `marketplace_order_id != null` (pedido comercial). Eliminar toda ruta `delivery_requests` quebraría Envíos.

## 2. Inventario contrastado con archivos de código existentes en `main`

| Área | Archivos fuente / contrato | Estado e instrucciones |
| --- | --- | --- |
| Startup, login, identidad | `lib/mobile_main.dart`, `lib/web_main.dart`, `lib/auth_entry.dart`, `lib/connected_shell.dart`, `lib/core/runtime_channel.dart` | Mantener la misma lógica Flutter en Web/Android y entorno resuelto por la cuenta. Preview/Producción no son dos aplicaciones web. |
| Cliente Taxi y Envíos | `lib/video_style_home.dart`, `lib/connected_experience.dart`, `lib/services/express_service.dart`, `lib/service_tracking.dart` | Código compartido map-first, ofertas, tarifa, ruta, PIN Taxi, etapas de Envíos, seguimiento. No bifurcar ni reescribir motor. |
| Cliente restaurantes | `lib/express_delivery_v2_page.dart`, `lib/express_marketplace_page.dart`, `lib/marketplace_category_page.dart`, `lib/marketplace_checkout_page.dart`, `lib/connected_experience.dart` | **SE CONSERVA en Principal**: catálogo → producto/extras → carrito → checkout → seguimiento → pedido/reseñas. No trasladar con el portal del negocio. |
| Conductor Principal | `lib/video_style_home.dart`, `lib/core/driver_work_scope.dart`, `lib/driver_work_permissions_page.dart` | PR #235 **fusionada**. Nuevas ofertas de conductor filtradas a `ride` y `parcel`; excluir pedidos con `marketplace_order_id`. Mantener posibilidad de terminar asignaciones comerciales históricas hasta migración segura. |
| Portal del comercio legacy | `lib/restaurant_portal_web.dart`, `lib/marketplace_merchant_page.dart`, `lib/marketplace_merchant_catalogue.dart`, `lib/marketplace_merchant_settlements.dart`, `lib/marketplace_chat_attachments.dart` | Código existente **a reutilizar/migrar** a `Express_Restaurante`; no borrar del Principal mientras no se comprueben acceso, pedidos activos, permisos y despliegue del reemplazo. |
| Admin Delivery | `Adminexpress/lib/admin_delivery_unified.dart`, `admin_marketplace.dart`, `admin_marketplace_phase2.dart`, `admin_marketplace_demos.dart`, `admin_delivery_settlements.dart`, `partner_panel.dart` | Administración permanece solo en `Adminexpress`. Demos/Marketplace tienen reglas propias por zona y canal. |
| Despacho, push, presencia | `lib/push_notifications_native.dart`, `lib/push_notifications_web.dart`, `lib/push_deduplication.dart`, `supabase/functions/express-push-dispatch/index.ts`, RPCs despacho SQL | **RIESGO P0:** el filtro Flutter no sustituye el aislamiento backend de tokens FCM, roles, paquetes y pedidos comerciales por app. Falta prueba E2E antes de retirar reparto legacy. |
| Llamadas privadas | `lib/private_voice_call.dart`, `lib/voice_call_browser.dart`, `web/express_voice_call.js`, `supabase/functions/zego-call/index.ts` | Web SDK específico en `main` por PR #230. Audio privado de Taxi/Envíos con token firmado. PR #236 propone quitar apariencia de videollamada Web, aún **NO fusionada**. PRs #232/#233 son cambios alternativos con posibles conflictos. |
| Moneda y tarifas | `lib/money_format.dart`, `lib/passenger_ride_currency.dart`, `lib/marketplace_checkout_page.dart`, RPC de cotización, Admin Tarifas | Chile CLP / Bolivia BOB; backend autoritativo, nunca reemplazar con precio fijo ni moneda por defecto. Push debe utilizar moneda del país/zona. |
| Seguridad/rol/entorno | `lib/core/runtime_channel.dart`, RPCs `admin_access_context` y permisos de negocio, RLS | Debe aplicarse en servidor, no solo ocultando botones. Respetar Preview vs Producción, ciudad/zona, usuario, comercio y conductor asignado. |
| QA y publicación | `.github/workflows/`, `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`, `Adminexpress/lib/admin_single_app_release.dart` | Probar Web primero; Android oficial solo por pedido expreso, firmado, trazado y probado. No crear una APK Preview paralela permanente. |

**Observación técnica:** `market`, `marketplace_*` y `marketplace_order_id` siguen siendo identificadores internos de base de datos y código legacy; el nombre **VISIBLE al usuario** debe usar «Delivery», «Restaurantes» y «Express Plus» según contexto. No renombrar tablas/RPC a ciegas: existen dependencias en Admin, checkout y migraciones.

## 3. Qué ya se retiró o separó (NO restaurar por accidente)

1. **Admin embebido en Express:** eliminados `lib/admin_panel.dart`, `lib/admin_control_sections.dart`, antiguo `lib/main.dart` y previews/prototipos antiguos. Reemplazo: `jorge2610g/Adminexpress`; documentado en README/historial.
2. **Startups Android divergentes:** `lib/mobile_main.dart` es la entrada funcional oficial. `lib/preview_main.dart` existe como wrapper de compatibilidad, no como una segunda app.
3. **Doble web Admin Preview/Producción:** reemplazada por un solo Admin y resolución de entorno mediante cuenta; no recrear `ADMIN_ENV` ni bundle `/preview/`.
4. **SDK de publicidad AdMob:** el changelog registra su retirada del proyecto. No reintroducir por una compilación antigua; conservar promociones internas de Express.
5. **Opciones UI redundantes en Admin:** la configuración de servicios por zona se unificó y «Servicios autorizados» del conductor se consolidó, sin duplicar la sección.
6. **Reparto comercial nuevo desde conductor Principal:** filtrado en PR #235, fusionada `2026-10-14T06:32:51Z`. **No equivale a desinstalar código legacy de entregas existentes, ni a haber lanzado la nueva app Repartidor.**
7. **Navegación directa de panel comercial desde perfil cliente:** retirada propuesta en PR #234, **no fusionada al corte**; no afirmar que ya desapareció de todas las builds.

## 4. Qué está aprobado para EXTRAER en el futuro (NO borrar todavía)

| Elemento | Destino/reemplazo | Condición ANTES de eliminarlo de Principal |
| --- | --- | --- |
| Panel de comercio y login `restaurant_portal_web.dart` | `Express_Restaurante` | Nueva web/app autenticada y desplegada con permisos por negocio, canal y zona; acceso a pedidos y liquidaciones reales probado. |
| Componentes `marketplace_merchant_*.` | `Express_Restaurante` | Reutilizar/refactorizar sin duplicar checkout cliente; test de catálogo, horarios, fotos, extras, promociones y gestión. |
| Recepción de nuevas ofertas `marketplace_order_id` en conductor Principal | `Express_Repartidor` | Registro de dispositivos por app, push selectiva, despacho backend y aceptar/rechazar/recoger/entregar E2E; compatibilidad con pedidos ya activos. |
| Nombres visuales «Market» / «Mercados» | «Delivery» / «Restaurantes» según sección | Corregir labels, rutas, pruebas y traducciones; **no** cambiar schema `marketplace_*` sin migración compatible. PR #234 lo prepara parcialmente. |
| Duplicados/históricos no utilizados | Limpieza por fases | Inventario de imports/rutas y consumidores en Web, Android, Admin y Supabase; respaldo y test previo, sin `DROP` ni borrado masivo. |

**No se va a quitar:** Taxi, cliente Envíos, cliente Delivery/restaurantes, conductor Taxi, conductor Envíos, backend compartido, permisos/KYC, historial, liquidaciones, pedidos existentes, ni la posibilidad de completar un servicio activo.

## 5. Trabajo PLANEADO y pendientes (orden recomendado; no confundir con realizado)

**P0 — Integridad operativa antes de retirar definitivamente legacy**
- Construir la app `Express_Repartidor` (repositorio inicialmente solo con README): Flutter Android, ofertas comerciales con mapa, distancia/ruta, aceptar/rechazar/expiración, pedido asignado, recogida, viaje, entrega, confirmación y ganancias.
- Cambiar el despacho **autoritativo** y las notificaciones a identificación por app/instancia/dispositivo: evitar que una oferta comercial llegue al conductor de Taxi/Envíos o quede sin receptor. No basta un filtro visual Flutter.
- Validar una entrega de extremo a extremo: cliente Principal compra → comercio acepta → repartidor comercial recibe push/oferta → recoge → entrega → cliente rastrea → liquidación/historial, con aislamiento Preview/Producción y zonas. Proteger pedidos históricos.
- Probar flujos Taxi y Envíos completos con clientes/conductores; sin disparar pedidos reales de prueba y sin activar módulos de Producción por accidente.

**P1 — App `Express_Restaurante` desde el mockup aprobado**
- Repositorio nuevo estaba vacío al corte; usar lógica UI comercial que ya existe como base, no copiar todo `Expressdelivery`. Plataforma web + Android con misma marca Express, tema claro/oscuro y permisos negocio.
- Pantallas de referencia del mockup interactivo: **acceso/selección del negocio**, inicio/KPIs, bandeja de pedidos nuevos/en preparación/listos/completados, detalle y acciones de pedido, catálogo/categorías/productos/modificadores, inventario/horarios, promociones, liquidaciones/ganancias, perfil y ajustes, notificaciones.
- El mockup era **simulado**, no un módulo funcional publicado. Crear UI interactiva y validar con el propietario antes de conectarla con pedidos, pagos y notificaciones reales.
- Diseñar Android para avisos/pedidos/operación y web para gestión completa. El comercio no debe entrar al panel administrativo global por tener restaurante.
- Conservar el cliente Delivery principal: restaurantes, producto, carrito, checkout, seguimiento, cupones, Express Plus y reseñas.

**P1 — Clientes: ajustes UI y flujos comerciales abiertos**
- PR #234 **abierta**: «Mis cupones» y Express Plus con diseño de referencia; mover «Mercados» a «Restaurantes», «Market» visible a «Delivery»; eliminar «Panel del Comercio» del perfil cliente. Requiere migración de cupones y QA, **no marcar como desplegado**.
- Revisar seguimiento de pedido que devolvía «No pudimos cargar la solicitud», permiso/RPC/estado al abrir de nuevo, y confirmar los comercios demos visibles por canal y ciudad.
- Cuadrar contadores de comercio (pendientes de publicar / ocultos para clientes) con sus filtros verdaderos. Ocho por publicar y tres ocultos **pueden pertenecer a filtros diferentes**, no asumir pérdida de datos ni publicar automáticamente.
- Demos Iquique/Trinidad y eventual carga desde negocios públicos: recopilar logo/menú **solo de fuentes utilizables y con derechos**, distinguir demo y negocio real, no suplantar ni inventar existencia/afiliación. Segregar Preview frente a demo Producción; nunca habilitar pedidos/pagos falsos sobre cuentas reales.
- Revisión integral CLP/BOB y push de valores de tarifa/pedidos, sin secretos ni importes ficticios.

**P1 — Llamadas Web / Android**
- PR #230 **fusionada**: integración Web por SDK ZEGO Web. La llamada ya puede usar signaling Web; requiere E2E documentado.
- PR #236 **borrador**: estilo de llamada normal (sin dos recuadros de videollamada) en Chrome para Taxi y Envíos. PR #233 persigue efecto visual similar; elegir una sola implementación, evitar fusionar ambos sin reconciliar. PR #232 modifica la sesión ZIM, revisar compatibilidad y eventual rebase.
- Probar Chrome↔Android / Chrome↔Chrome / Android↔Android, voz bilateral, llamada entrante en segundo plano, aceptar, rechazo, colgar, cooldown y privacidad. La captura anterior mostró recuadros aunque el audio entraba; no afirmar arreglo publicado mientras siga en PR.

**P2 — Admin, ajustes de negocio, observabilidad y mejoras posteriores**
- AdminExpress conserva control global de países/zonas, servicios visibles, autorizaciones por vehículo, demo, restaurantes, pedidos, liquidaciones, Plus, cupones, notificaciones y QA.
- Demanda en escalones exactos de ×0,5 solicitada, PR #222 pendiente por límite máximo y cambios al cálculo real; no redondear solo etiqueta.
- PR #228 (evitar mostrar foto antigua del conductor) abierta; pendiente QA.
- Monitorización y optimización de backend/cachés sin falsear saldos, rutas ni tarifa; manejar errores de fallbacks y no saturar logs.

## 6. Inventario de PR relevantes y riesgo de interpretar «listo»

| Cambio | Referencia | Estado verificado en GitHub al corte |
| --- | --- | --- |
| ZEGO Web básico | #230 | **FUSIONADO** (integración Web en `main`) |
| Extraer ofertas comerciales del conductor Principal | #235 | **FUSIONADO** (código en `main`) |
| UI llamada Web sin recuadros | #236 | **ABIERTA / BORRADOR**, sin integrar |
| UI alternativa de llamada Web | #233 | **ABIERTA**, posible solapamiento con #236 |
| Sesión ZIM Web | #232 | **ABIERTA**, pendiente reconciliar con Web actual |
| Cupones + Plus + renombrado UI | #234 | **ABIERTA**, falta migración/QA para activar |
| Foto vigente del conductor sin parpadeo | #228 | **ABIERTA**, aún no liberada |
| Demanda ×0,5 escalonada | #222 | **ABIERTA / NO APROBAR**, backend de precios pendiente |
| PR #224 antiguo bridge Web | #224 | **BORRADOR histórico**; #230 es implementación posterior |

Consultar PRs reales antes de cambiar un estado. Que una PR esté abierta no significa que nunca haya código equivalente en `main`; comparar diff contra la base actual y probar.

## 7. Build Android y estado de lanzamiento

- Último build citado por propietario como subido a Google Play: **139** (declaración del propietario; no equivale a verificación independiente Play Console).
- Candidato **1.6.1+140** generado como APK+AAB firmados (firma Producción) a partir del **SHA exacto `61a83ae290a94c456d1a53728ed1ff34198975b3`**. GitHub Actions `38524874786`; trabajo Supabase `72f59486-6db1-4498-a825-77c8615ae184`.
- Release GitHub: `single-app-android-qa-v1.6.1-build140-sha61a83ae290a9-job72f59486` (APK, AAB, identity.json).
- SHA-256 APK `c173b1414b62e1bc387ab71064ee5306a7ea648810eaa80acffa15732b363d5a`; AAB `f9aef8097913dfa8712ab72509182529a1ef1f7996cef2ab5ad3fbadfd417338`.
- Base del registro de Play en Supabase: `production_store_build_number=139`, siguiente `140`; **no es confirmación de publicación de 140**.
- Estado: build y firma CI **correctos**, aprobación QA física y promoción administrativa **no confirmadas**. APK y AAB son candidatos para probar/Subir a testing, no release certificada a clientes.
- El SHA de build 140 NO es automáticamente igual al `main` actual (inspeccionado `f92bc2...`); no recompilar/renombrar los artefactos bajo otra identidad.
- PR #236 (solo Web) **no se incluye en build 140**. No afirmar que desapareció la apariencia de videollamada en la 140.

## 8. Contratos de seguridad y compatibilidad que NO deben romperse

1. Identidad única cliente/conductor en Principal; `active_mode` y autorizaciones de conductor; no habilitar repartidor comercial por rol de Taxi.
2. Separar runtime `preview`/`production` desde backend y cuenta, no URL ni botón; zonas/catálogos/moneda y permisos por rol.
3. Servidor es autoridad para precio, ofertas, cuota, comisión, billetera, pagos, seguridad y estados. Sin datos de demo mezclados con dinero real.
4. Conductores aprobados solo ven solicitudes compatibles con zona, vehículo, modalidad, tiempo/alcance y capacidad; grants Moto/Auto/Carga no se saltan.
5. Envíos de particulares (`parcel`) y pedidos comerciales (`market`) pueden usar partes del backend histórico, pero **no compartir nuevas ofertas en Principal**.
6. Llamada de Taxi/Envíos usa ZEGOCLOUD con Token04 backend; no mostrar teléfonos ni abrir `tel:` para participantes internos. La llamada externa al destinatario no registrado de Envíos es excepción explícita existente.
7. No publicar una migración destructiva sin auditoría de consumidores (apps antiguas instaladas, Web, Admin y nuevas apps), plan de rollback y pruebas RLS.
8. No guardar secretos, tokens, credenciales Firebase privadas, keystore ni firma en repos.
9. Preservar nombre de paquete oficial `com.express.usuario1`, firma y contador de versión Google Play.
10. Publicación Web común para cuentas Preview/Producción según permiso; **habilitación comercial por zona/canal es independiente de tener código desplegado**.

## 9. Pasos obligatorios para continuar la división sin perder servicio

1. Releer este documento + `docs/PRIMARY_DRIVER_MARKET_SPLIT_2026-10-14.md`, `AGENTS.md`, handoff, changelog y README de los otros tres repos.
2. Confirmar SHA actual de `main`, builds y PR abiertas antes de editar; mantener rama de respaldo y una rama de trabajo por entrega.
3. Registrar lista de imports, RPC, tablas, push, RLS y pantallas usadas por cada aplicación; crear pruebas de aislamiento por app/canal/servicio y rutas UI.
4. Construir Express Restaurante y Express Repartidor *sin* eliminar componentes de Principal; conservar backend compatible para APK anteriores.
5. Verificar integración real de pedidos/envíos/viajes y notificaciones con dispositivos + cuentas diferentes; efectuar QA de zona Preview, Iquique/Trinidad y moneda local.
6. Cambiar el backend a despacho comercial por app **solo cuando la nueva Repartidor esté lista**; impedir pedidos sin repartidor.
7. Migrar portada/portal de negocio y solamente entonces retirar código comercial legacy del principal que no usa el cliente; preservar historial y entregas activas.
8. Auditar API/RLS, monitorear fallos, obtener aprobación de QA; luego liberar sin reconstruir el binario aprobado bajo SHA distinto.
9. Cada código retirado se documenta con archivo, reemplazo, PR/SHA, prueba y rollback. **Sin operaciones destructivas automáticas**.

## 10. Límites de esta auditoría

Se examinó el árbol completo de archivos GitHub de Principal (456 entradas) y Admin (102), se contrastaron los archivos mayores y contratos de los módulos principales, PRs y release/gate oficial. **No constituye revisión línea por línea de cada migración histórica ni pruebas reales en teléfonos**, ni garantiza que el estado de Producción de cada zona/demo esté idéntico a un documento del 12 de octubre. Los datos y despliegues concretos deben comprobarse al ejecutar cada fase. La intención es un mapa verificable de continuidad, no declarar cerrados bugs sin evidencia.

## Referencias

- Arquitectura extracción: `docs/PRIMARY_DRIVER_MARKET_SPLIT_2026-10-14.md`
- Apps Android/Web: `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`
- Flujos Delivery: `docs/EXPRESS_DELIVERY_V2_IMPLEMENTATION.md`
- Demos: `docs/EXPRESS_DELIVERY_DEMOS_20261012.md`
- Autorizaciones: `docs/DRIVER_WORK_PERMISSIONS_QA_20261013.md`
- Privacidad/audio: `docs/PRIVATE_VOICE_CALLS.md`
- Entornos: `docs/PREVIEW_PRODUCTION_RELEASE_ARCHITECTURE.md`
- Reglas de cambios: `docs/DOCUMENTATION_POLICY.md`
- Historial: `docs/CHANGELOG_ACTIVE.md`
