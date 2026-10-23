# Express Principal — Taxi, Envíos y Delivery

> **Continuidad vigente: 2026-10-23.** Esta sección sustituye el estado operativo antiguo que sigue más abajo como historial. La referencia para la candidata 1.6.3+144 es [su bitácora de QA y publicación](docs/BUILD_144_CHANGELOG.md); respetar también [AGENTS.md](AGENTS.md) y el contrato de [aplicación única y Web First](docs/SINGLE_APP_WEB_FIRST_2026-10-08.md).

## Estado de continuidad — 2026-10-23

- PR #270 está integrado en `main`; su despliegue web oficial y los cambios de deuda por cancelación están documentados en la bitácora 144. PR #274 es el seguimiento abierto para inicio/GPS, registro web y correcciones de permisos al iniciar llamadas. Consultar GitHub para el SHA y los checks vigentes antes de crear una release.
- QA reciente en `emulator-5554` (API 37) y `emulator-5556` (API 34): Express abre en ambos, el mapa base carga, y no se observa un diálogo de micrófono al entrar al viaje activo. La pantalla del pasajero muestra tarifa, PIN y botón Waze; la del conductor conserva el estado del viaje. Esta revisión visual no crea ni cancela viajes y no sustituye pruebas de pagos o deudas.
- Se encontró que ZEGO usa permisos de cámara/micrófono por defecto cuando `permissions` se omite. La sincronización de sesión ahora especifica una lista vacía; la app solicita micrófono al conductor justo antes de iniciar una llamada saliente. Debe verificarse en CI y en la APK temporal de la misma revisión antes de considerar el cambio listo.
- La ruta directa temporal no debe presentarse como ruta vial. Si el servicio de rutas tarda o falla, se conservan el mapa y los marcadores sin dibujar una línea recta engañosa; una geometría vial aparece cuando responde el servicio existente. No añadir un proveedor pago ni aumentar consultas de mapas.
- No generar artefactos oficiales ni enviar AAB a Play hasta que el SHA final tenga CI verde y QA visual conforme en ambos AVD. Cualquier carga autorizada es solo a Pruebas internas; Producción requiere aprobación separada. No crear cuentas, viajes o deudas reales para verificar.
- La configuración de correo de aprobación sigue aplazada. No aplicar la migración ni configurar secretos de correo sin una instrucción nueva.

Las secciones siguientes conservan decisiones y antecedentes históricos; si chocan con esta continuidad o con `AGENTS.md`, aplicar la información vigente de arriba.

## Aplicación principal: cinco recorridos

1. Cliente Taxi.
2. Cliente Envíos/paquetería.
3. Cliente Delivery y compra de restaurantes/tiendas (producto, carrito, checkout, seguimiento).
4. Conductor Taxi.
5. Conductor Envíos/paquetería.

**Solo el reparto de pedidos comerciales sale del conductor Principal.** Este primer filtro fue fusionado mediante PR #235; el reemplazo en nueva app y la segmentación backend/push no están terminados. No quitar pedidos cliente ni borrar código/RPC de la tabla legacy `delivery_requests`.

## Aplicaciones independientes

| Aplicación | Repositorio | Estado al corte |
| --- | --- | --- |
| Express Principal | `jorge2610g/Expressdelivery` | Funciones existentes + PR #235 fusionada. |
| Express Restaurante | `jorge2610g/Express_Restaurante` | Nuevo repo, **app funcional pendiente**; portal comercial existente sigue en Principal. |
| Express Repartidor | `jorge2610g/Express_Repartidor` | Nuevo repo con README, **app funcional pendiente**; no Taxi ni Envíos entre personas. |
| Express Admin | `jorge2610g/Adminexpress` | Panel Web independiente y compartido por permisos/canal. |

## Código y dominios

- Android oficial `com.express.usuario1`: `lib/mobile_main.dart`.
- Web oficial `https://expressviajes.online/`: `lib/web_main.dart`.
- Portal comercial heredado: `lib/restaurant_portal_web.dart` + `lib/marketplace_merchant_*.dart`, **no borrar todavía**.
- Administración: `https://admin.expressviajes.online/`; no incrustar Admin en Principal.
- Backend: Supabase `zgpijrznvaskgcmauwxx`. Preview y Producción comparten frontend, pero separan datos por cuenta/canal y servicios por zona.
- Web/Android, firma y despliegues: [Guía de lanzamiento](docs/SINGLE_APP_WEB_FIRST_2026-10-08.md).

## Última build Android conocida

**Candidato `1.6.1+140`** firmado en GitHub, desde SHA `61a83ae290a94c456d1a53728ed1ff34198975b3`, run `38524874786`; APK y AAB listos, QA física y publicación pública **no confirmadas**. El propietario reportó que subió la 139. No deducir el contenido de APK 140 por el HEAD actual de `main`.

## Cambios y pendientes importantes

- **Fusionado:** PR #230, ZEGO Web; PR #235, exclusión de nuevos pedidos de restaurante del conductor Principal.
- **Fusionados el 14/10:** PR #241 (foto privada estable), #238 (historial de Envíos antiguos), #240 (reconexión ZEGO al volver), #157 (filtros de Actividad) y #234 (Mis cupones/Express Plus). **Main fusionado no implica APK generada, QA física ni publicación Play**. CI integrado `38652146204`: 117 tests PASS, análisis Flutter y compilación Web PASS.
- **Consolidados el 14/10:** PR #242 (llamada Web con interfaz telefónica solo audio) y #243 (filtrar Realtime de otra zona/canal antes de recargar conductor); correcciones adicionales `7832ac820` (permiso backend para conectar conductor) y `8c63b8d31` (notificación de corrección documental). Respaldos preservados. **No se compiló otra APK ni se verificó E2E nativo.**
- **Archivados, no mezclar:** #228 (variante foto ya sustituida), #236/#233 (dos diseños alternativos Web ya absorbidos en #242), #164 (acceso de conductor ya corregido), #160/#196 (Preview APK/web paralelos retirados), #161 (documentos obsoletos), #224 (SDK de llamada Web obsoleto).
- **Pendiente/no fusionar a ciegas:** #150 (filtro servidor/throttle profundo, requiere medir ofertas; #243 es solo el filtro local seguro), #155 (revisión por foto requiere Admin+SQL+QA), #199 (RPC antiguos por zona), #202 (repartos comerciales no pertenecen al conductor principal), #222 (demanda 0,5 sin techo de tarifa definido), #190 (premios a billetera requieren autorización financiera), #172 y #163 (alternativas antiguas de conductor a reconciliar).
- **Inventario de próxima APK única:** [Android readiness](docs/ANDROID_OFFICIAL_NEXT_CANDIDATE_READINESS_20261014.md).
- **Plan:** nueva app Comercio con mockup aprobado; nueva app Repartidor con push y dispatch segregados; quitar portal comercial heredado solo al culminar migración E2E, preservando Taxi y Envíos.

Los archivos históricos pueden mencionar «solo Taxi», «build 131», «Preview Shorebird» u otros estados anteriores. **No son la fuente actual.** Revisar siempre la auditoría, PRs, workflows y release/gate antes de actuar.

## Continuidad obligatoria

- [Auditoría y roadmap técnico](docs/EXPRESS_CODE_AUDIT_AND_FOUR_APP_PLAN_20261014.md)
- [Alcance de extracción de conductor](docs/PRIMARY_DRIVER_MARKET_SPLIT_2026-10-14.md)
- [Delivery V2](docs/EXPRESS_DELIVERY_V2_IMPLEMENTATION.md)
- [Política de documentación](docs/DOCUMENTATION_POLICY.md)
- [Historial de cambios](docs/CHANGELOG_ACTIVE.md)
