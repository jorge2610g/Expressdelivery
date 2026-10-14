# Express Principal — Taxi, Envíos y Delivery

> **Último corte documental: 2026-10-14.** Para no romper el sistema, leer **primero** [Auditoría del código y plan de cuatro aplicaciones](docs/EXPRESS_CODE_AUDIT_AND_FOUR_APP_PLAN_20261014.md), [AGENTS.md](AGENTS.md) y [arquitectura de aplicación única](docs/SINGLE_APP_WEB_FIRST_2026-10-08.md).

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
