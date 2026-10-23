# Vigencia de solicitudes y ofertas: análisis (producción, solo lectura)

## Dónde se configura
- Tabla `public.app_settings`: **una sola fila global** (`id = true`). No hay ajustes por zona ni por servicio.
- Valores de producción (2026-10-16): `offer_timeout_seconds = 20`, `search_timeout_seconds = 180`, `request_visible_seconds` (función de visibilidad: 180 por defecto).
- Ajustes de búsqueda y visibilidad: `admin_advanced_settings_update` (migración 030) los escribe con límites 30..1800.
- `offer_timeout_seconds`: no existe función administrativa en este repositorio; solo la migración 004 lo fijó a 20. Si el panel de administración lo escribe directamente, eso está en otro repositorio (Adminexpress) y no pude verificarlo desde aquí.

## Qué usa cada ajuste
| Ajuste | Usado por | Efecto |
|---|---|---|
| `search_timeout_seconds` (180) | `createRideRequest` (cliente) | `ride_requests.expires_at = creación + 180 s`: **tiempo total de búsqueda de la solicitud** |
| `request_visible_seconds` (180) | `available_ride_requests_for_driver` (producción) | Ventana en la que un conductor ve la solicitud |
| `offer_timeout_seconds` (20) | `createRideOffer` (cliente, envía `expires_at = ahora + timeout`) y `express-push-dispatch` (dato de metadatos) | Intención de vigencia **de cada oferta** |

## Lo que sucede realmente
- Los triggers `trg_driver_offer_deadline` (15 s) y `trg_enforce_driver_offer_minimum_lifetime` (30 s) **sobrescriben** el `expires_at` del cliente. Efecto: **30 s fijos** por oferta. Verificado en datos (7 días: mediana 30–31 s, 0 nulos).
- `offer_timeout_seconds` queda **ignorado**. Verificado localmente: configurado a 20 s o 120 s, la vigencia sigue en 30 s (L1, L2 en baseline).
- Las solicitudes sí duran ~180 s (mediana 179 s en 7 días).
- **Gap de solicitud:** `select_ride_offer` no comprobaba `ride_requests.expires_at`. Una oferta vigente podía aceptarse después de vencer la solicitud (L4 en baseline). Y se podía insertar una oferta sobre una solicitud ya vencida (L3).
- `cleanup_expired_ride_requests` cancela solicitudes vencidas, pero **solo se ejecuta cuando alguien la llama**. No encontré ninguna programación (cron) en el repositorio. El cliente llama a `cleanup_expired_ride_offers` periódicamente, no a la de solicitudes.

## ¿180 s son el total de búsqueda, de cada oferta o de ambos?
- **Total de búsqueda (solicitud): sí.** Es `search_timeout_seconds` y es lo que dura la solicitud.
- **Cada oferta: no.** La oferta debe durar `offer_timeout_seconds` (20 s en producción), no 180 s.
- **Por tanto, no se deben pasar todas las ofertas a 180 s.** Hacerlo convertiría la vigencia de la oferta en 3 minutos, cuando la configuración dice 20 s.

## Aviso flotante de 15 s
- Verificado en código nativo (`FloatingOfferService.kt`): la tarjeta se cierra en `min(vencimiento de la oferta, 15 s)` (`getVisualDeadline`). Nunca sobrevive a la oferta y nunca alarga su vigencia.
- La vigencia de la oferta no depende del aviso. **Requisito cumplido sin cambios.**

## Propuesta v3 (no desplegada)
Archivo: `docs/pending_migrations/20261016_offer_lifetime_v3_proposal.sql`.
1. Vigencia de la oferta = `offer_timeout_seconds` (acotado 10..600), sin superar `ride_requests.expires_at`.
2. Solicitud vencida: no admite ofertas nuevas (`La solicitud ya venció`) ni selección (`r.expires_at > now()`).
3. Pendiente nunca nulo.
4. Incluye la guardia v2 (oferta no nula y vigente).

## Resultados locales (PostgreSQL 15 aislado, triggers reales)
- Baseline: L1 FAIL, L2 FAIL, L3 FAIL, L4 FAIL, T4 FAIL (defectos confirmados); T1, T2, T3, T5, T6, E1 (Envíos), carrera 50/50 PASS.
- Propuesta v3: **18/18 PASS** (L1–L4, T1–T6, E1 Envíos con texto de notificación vigente, bloqueo, carrera 50/50, 0 inconsistencias).
- Registros: `results_lifetime_baseline.txt`, `results_lifetime_v3.txt`. Reproducción: `run_lifetime.sh`.

## Decisión pendiente (no cambiada automáticamente)
- **Confirmar la vigencia de oferta:** producción dice 20 s, la app muestra al conductor ~30 s hoy. Con v3 el conductor dispondrá de 20 s. Requiere confirmación antes de desplegar.
- Confirmar si `offer_timeout_seconds` lo escribe el panel de Adminexpress y cómo.
- Decidir si se programa `cleanup_expired_ride_requests` (no necesario con v3 para la aceptación, sí para la limpieza de datos).
