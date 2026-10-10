# SPEC 2026-10-10 — Pasajero: quitar flecha atrás sobre las ofertas y separar "Viajes programados"

**Estado:** lista para la IA programadora. Claude revisa después.
**Repo:** `jorge2610g/Expressdelivery` · rama nueva desde `main` (p. ej. `chatgpt/passenger-offers-scheduled-menu`). Solo Dart; sin backend.
**Nota:** `lib/video_style_home.dart` también lo toca el PR #150. Cambios mínimos; el que se fusione segundo resuelve el conflicto.

## Tarea 1 — Flecha "atrás" encima de "Cancelar solicitud" (pantalla "Elige a un conductor")

**Evidencia** (captura del propietario 9:32 y `main`):
- Cuando llegan ofertas, `_OfferWaitingPanel`/panel de ofertas dibuja el botón rojo `Cancelar solicitud` arriba a la izquierda (`lib/video_style_home.dart` ~12597-12614).
- Al mismo tiempo, el `Stack` del mapa dibuja otro botón circular con flecha atrás en la misma esquina (`lib/video_style_home.dart` ~5233-5246):
```dart
if (hasPassengerOffers && !passengerFlowMinimized && passengerFlowActive)
  Positioned(top: 10, left: 14, child: SafeArea(bottom: false,
    child: _CircleButton(icon: Icons.arrow_back_rounded, onPressed: _backFromPassengerFlow))),
```
  Los dos se superponen.

**Cambio:** eliminar ese bloque `Positioned` completo. No cambiar `Cancelar solicitud` ni la lógica de ofertas.

**Comportamiento esperado:**
- Con ofertas visibles: solo se ven `Cancelar solicitud`, el título y las tarjetas de oferta.
- `Cancelar solicitud` → cancela (`_cancelOpenRide`) y vuelve al panel principal (comportamiento actual).
- Cuando se acaban o vencen las ofertas: la pantalla vuelve al panel de espera o al panel principal como hoy (la barra superior con su botón reaparece porque `effectivePassengerOffers` queda vacío, línea ~4982).

## Tarea 2 — "Mis servicios" y "Viajes programados" hacen lo mismo

**Evidencia** (`main`):
- Menú del pasajero `_showPassengerMenu()` (`lib/video_style_home.dart` ~4295-4330): `Mis servicios` y `Viajes programados` llaman ambos `widget.onHistory()`.
- `onHistory` en `lib/connected_experience.dart:880-883` → `index = 1` → `ExpressHistoryPage(service, driver: false)` (`connected_experience.dart:1060`).
- `ExpressHistoryPage` (`lib/express_account_pages.dart:184`) solo tiene filtros `all`, `completed`, `cancelled` (líneas ~294-393): **no existe vista de programados**.
- El filtro `Programados` existe solo en `_CustomerActivity` (`connected_experience.dart:2184-2423`), que **no se usa en ninguna parte** (código muerto).
- Los viajes programados usan `ride_requests.scheduled_for`. El ajuste `settings['scheduled_rides_enabled'] == false` desactiva la función (`video_style_home.dart:1422`, `:5922`).

**Cambio:**
1. `ExpressHistoryPage`: nuevo parámetro `final String initialFilter` (default `'all'`); el estado arranca con `filter = widget.initialFilter`. Agregar, solo cuando `!widget.driver`, el chip `Programados` (icono `Icons.event_outlined`, valor `'scheduled'`) que muestra las entradas con `scheduled_for` no nulo. Si `_load()` hoy no trae las solicitudes programadas del pasajero, incluirlas con el método existente del servicio que lee `ride_requests` del usuario (sin RPC nueva). Estado vacío: `No tienes viajes programados.`
2. `video_style_home.dart`: nuevo callback `final VoidCallback onScheduledTrips;` en el widget del pasajero que hoy recibe `onHistory` (constructor ~línea 992). En el menú, `Viajes programados` llama `widget.onScheduledTrips()`. Ocultar ese ítem cuando `settings['scheduled_rides_enabled'] == false`, con la misma fuente de `settings` que usa `_chooseSchedule`.
3. `connected_experience.dart`: estado `String historyInitialFilter = 'all';`. `onHistory` → `historyInitialFilter = 'all'; index = 1`. `onScheduledTrips` → `historyInitialFilter = 'scheduled'; index = 1`. Crear la página con `ExpressHistoryPage(key: ValueKey('history-$historyInitialFilter'), service: …, driver: false, initialFilter: historyInitialFilter)`.
4. Eliminar `_CustomerActivity` y su `_ActivityFilterChip` **solo si** quedan sin uso tras el cambio (verificar con `grep`).

## Restricciones
- Sin cambios de backend, Supabase, Edge Functions ni Producción.
- No tocar la lógica de ofertas, cancelación ni el modo conductor.
- Textos en español.

## Cómo probar
1. `flutter analyze --no-fatal-warnings --no-fatal-infos lib` sin errores fatales; `flutter test` en verde.
2. Test de widget o unitario para `ExpressHistoryPage(initialFilter: 'scheduled')` que verifique que solo muestra entradas con `scheduled_for`.
3. Manual (APK QA con etiqueta `native-qa` o Web Preview):
   - Pedir viaje, esperar una oferta: no hay flecha encima de `Cancelar solicitud`; cancelar vuelve al panel principal; dejar vencer las ofertas vuelve al panel normal.
   - Menú → `Mis servicios` abre el historial en "Todos"; menú → `Viajes programados` abre el historial con "Programados" seleccionado; con `scheduled_rides_enabled = false` el ítem no aparece.
4. Capturas de ambos casos.

## Formato de devolución
`docs/AI_RESPONSE_FORMAT.md`: commit, PR, archivos, salida de analyze/test y capturas.

---

## PROMPT PARA LA IA PROGRAMADORA

Repo `jorge2610g/Expressdelivery`. Lee `docs/specs/SPEC-2026-10-10-passenger-offer-back-and-scheduled-menu.md` (rama `claude/express-admin-audit-cp07ml`) y ejecútala en una rama nueva desde `main` (p. ej. `chatgpt/passenger-offers-scheduled-menu`):
1. **Tarea 1:** elimina el `Positioned` con `_CircleButton(Icons.arrow_back_rounded, _backFromPassengerFlow)` que aparece cuando hay ofertas (`lib/video_style_home.dart` ~5233-5246). No cambies `Cancelar solicitud`.
2. **Tarea 2:** separa `Viajes programados` de `Mis servicios`:
   - `ExpressHistoryPage` recibe `initialFilter` y suma el chip `Programados` (`scheduled_for` no nulo).
   - Nuevo callback `onScheduledTrips` desde el menú del pasajero hasta `connected_experience.dart`.
   - `ValueKey` por filtro.
   - Oculta el ítem si `scheduled_rides_enabled == false`.
   - Borra `_CustomerActivity` solo si queda sin uso.

Sin cambios de backend. No fusiones. Pruebas: analyze, test (incluye uno para el filtro `scheduled`) y capturas manuales. Abre un PR a `main` y devuelve el resultado con el formato de `docs/AI_RESPONSE_FORMAT.md`.
