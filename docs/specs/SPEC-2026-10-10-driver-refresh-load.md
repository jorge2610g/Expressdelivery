# [SPEC] Reducir recargas del panel del conductor (Preview primero)

> Autor: Claude (arquitecto/revisor). Implementación: IA programadora (Codex / ChatGPT / otra).
> Claude NO programa esta spec; solo la revisa.

## Contexto y evidencia (solo lectura, 2026-10-10)
- Logs de Supabase `zgpijrznvaskgcmauwxx`: un conductor generó ~20 llamadas a `my_current_country_trips_v2` en 1 minuto (03:43–03:44 UTC).
- Causa en `lib/video_style_home.dart` (`DriverMapHome`, ~línea 6700–6760): `_refreshDriverHome()` (carga completa `_load()`, incluye `myTrips()` y `myDeliveries()`) se dispara desde:
  - `Timer.periodic(12 s)` (línea ~6753);
  - canal Realtime `ride_requests` **sin filtro** (línea ~6707): cualquier solicitud de cualquier pasajero de la base dispara un refresco completo en cada conductor;
  - canal `notifications` (línea ~6720), filtrado por usuario pero también por cada aviso de tipo `ride_request`;
  - canal `zone_service_catalog` **sin filtro** (línea ~6743).
- Hay 18 llamadas a `_refreshDriverHome()` en total.
- Impacto: costo de Supabase (lecturas y conexiones Realtime), batería/datos del teléfono y riesgo de cortes de red visibles (ver `CHANGELOG_ACTIVE.md`, entrada del 2026-10-10 sobre `expressFriendlyLoadError`).

## Objetivo
Que un conductor en línea haga **como máximo una lectura completa cada 12 s** y que los eventos de Realtime solo refresquen lo que les corresponde, sin cambiar el comportamiento visible de ofertas, viajes ni entregas.

## Fuera de alcance
- No cambiar RPC, migraciones, RLS ni Edge Functions.
- No cambiar la lógica de ofertas (`ride_offer`, `select_ride_offer_v2`) ni los textos.
- No tocar la app de pasajero ni el panel Admin.
- No desplegar nada a Producción; el cambio es Dart y se valida en Preview.

## Diseño requerido (pasos)
1. **Filtrar el canal `ride_requests` por zona/canal del conductor** en el servidor de Realtime (filtro `eq` por el campo que identifique la zona o el canal de la solicitud; confirmar el nombre de columna en `supabase/migrations` antes de codificar). Si no es posible filtrar en servidor, filtrar en cliente antes de llamar a `_refreshDriverHome()`.
2. **Throttle/debounce de refresco completo:** un único punto de entrada (`_requestDriverRefresh`) que agrupe disparos en una ventana de 2 s y nunca ejecute dos cargas concurrentes (ya existe `driverRefreshInFlight`; reutilizarlo).
3. **Refresco ligero para eventos que solo afectan a una parte:** `zone_service_catalog` debe actualizar solo la lista de servicios disponibles, no `myTrips()`/`myDeliveries()`.
4. **Timer de 12 s:** mantener como respaldo, pero omitirlo cuando hubo un refresco completo en los últimos 12 s.
5. **Mantener** el comportamiento de `_reconcileDriverHomeInBackground` y de los eventos de push en primer plano.

## Criterios de aceptación (verificables)
- A) Con un conductor en línea y sin actividad, en 60 s se hacen **≤ 5** llamadas a `my_current_country_trips_v2` (hoy ~20 por minuto en la captura).
- B) Una solicitud nueva de otra zona **no** dispara ninguna llamada a `my_current_country_trips_v2` en el conductor.
- C) Una oferta real sigue apareciendo en ≤ 2 s tras el evento (medido en Preview con dos dispositivos).
- D) `flutter analyze lib` sin errores; `flutter test` pasa (incluye `test/express_friendly_load_error_test.dart`).
- E) Nuevo test unitario del throttle: N disparos en 1 s producen 1 carga.

## Pruebas requeridas
- Unitarias: throttle (criterio E) y filtro de zona (función pura de decisión, extraída y testeada).
- Manual en Preview: 2 dispositivos conductor + 1 pasajero; medir conteo de llamadas en `function_edge_logs`/`edge_logs` (filtrar por `my_current_country_trips_v2` y el `user_id`) antes y después.
- Regresión: aceptar/rechazar oferta, viaje activo, entrega, cambio En línea/Offline.

## Riesgos
- Dejar de refrescar puede ocultar una oferta si el filtro de zona es incorrecto → criterio C es obligatorio antes de aprobar.
- APK instalados (Producción) no cambian hasta nuevo build; el cambio solo aplica tras release.

## Rollback
Revertir el commit en Dart; no hay cambios de backend.

## Documentación a actualizar
- `docs/CHANGELOG_ACTIVE.md` (entrada nueva con evidencia de antes/después).
- `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md`, punto 8b (marcar como resuelto con evidencia).

## Entrega esperada de la IA programadora
Rama `codex/driver-refresh-throttle`, PR que cite esta spec, tabla de conteos antes/después y resultados de `flutter analyze` y `flutter test`. Claude revisará contra los criterios A–E.
