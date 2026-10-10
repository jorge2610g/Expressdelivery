# Anuncios pasajeros: interruptor de Admin y unidades Android

Adminexpress expone `Configuración → Admin → Publicidad (Google AdMob)`. Las dos webs apuntan al Supabase principal y los RPC `admin_admob_settings_get/update` validan permisos de canal.

- Producción: `ads_passenger_enabled`, `ads_passenger_home_enabled`, `ads_passenger_trip_enabled`.
- Preview: `ads_passenger_preview_enabled`, `ads_passenger_preview_home_enabled`, `ads_passenger_preview_trip_enabled`.
- Preview usa siempre la unidad de prueba Google y no modifica los ID de producción.
- Identificadores públicos de monetización: `admob_publisher_id`, `admob_android_app_id`, `admob_passenger_banner_unit_id`. **No son secretos**. Nunca poner service-role, token de API o credenciales financieras aquí.
- El runtime de Express lee `app_runtime_config.settings` y consume los flags de ambiente. Los dos `PassengerAdSlot` se encuentran en `video_style_home.dart` (Inicio y viaje activo).
- La unidad Banner usa el ID remoto válido en Producción; si no existe, utiliza el fallback compilado `ADMOB_PASSENGER_BANNER_UNIT_ID`.
- El **App ID de Android debe compilarse en el Manifest**, desde el secreto GitHub Actions `ADMOB_ANDROID_APP_ID` (no cambia con Supabase). La APK instalada requiere una nueva versión para reemplazar un App ID de prueba.
- Ninguna actualización de SQL o Admin despliega por sí sola una APK o publica Google Play.
- Valores conservados: anuncios reales OFF hasta que el propietario configure y active correctamente AdMob.


## 2026-10-10 — Reparación del archivo móvil

`lib/passenger_ads_mobile.dart` estaba truncado desde `e37d7be` (Android no compilaba). Se restauró la versión con Banner ID remoto validado por `^ca-app-pub-[0-9]{16}/[0-9]{10}$`; Preview sigue usando siempre el ID de prueba de Google. Ver `CHANGELOG_ACTIVE.md`.
