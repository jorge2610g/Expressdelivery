# Revisión de Adminexpress (solo lectura) y valores de 180 s y 20 s

Repositorio: `jorge2610g/Adminexpress` (público, rama `main`, commit `c406639`). Revisión por clon superficial en carpeta temporal; sin cambios.

## Respuestas
1. **¿Existe control para `offer_timeout_seconds`?** Sí. Campo "Tiempo de oferta (segundos)" en `lib/admin_control_sections.dart` (~línea 7791 carga, ~7849 guarda).
2. **¿Guarda realmente en `app_settings`?** Sí en **producción**: el control llama al RPC `admin_settings_update` con `p_offer_timeout_seconds`. En producción el RPC escribe `offer_timeout_seconds = least(greatest(coalesce(p, 45), 10), 600)` en `app_settings` (verificado en el catálogo, solo lectura).
3. **¿Puede el administrador modificarlo?** Sí, en el panel de producción. **En Preview no tiene efecto sobre la app**: el panel guarda con `admin_environment_config_upsert` (módulo `app_settings`, clave `default`), y la app Express **no lee** esa tabla (0 referencias en el código de la app).
4. **¿Se refleja en el backend?** Sí. La app lee `app_runtime_config`, que lee `app_settings`. La creación de ofertas fuerza refresco (`appSettings(forceRefresh: true)`). La creación de solicitudes usa caché: 45 s para refrescar en segundo plano y hasta 10 min de validez máxima (`_configFreshFor`, `_configUsableFor`).
5. **¿Existe `search_timeout_seconds`?** Sí. Control en la sección avanzada (~línea 8390) con RPC `admin_advanced_settings_update` (límites 30..1800, defecto 180).
6. **¿Otros controles sobrescriben estos valores?** No. De las siete funciones que escriben en `app_settings`, ninguna toca `offer_timeout_seconds` ni `search_timeout_seconds` salvo las dos anteriores. Las demás actualizan solo sus columnas (anuncios, oferta flotante, verificación de teléfono).

## Defectos encontrados
- **Valor por defecto del panel: 45 s** (`?? 45`) frente a la base `offer_timeout_seconds = 20`. No afecta mientras la fila tenga valor; sí si la fila no lo tiene.
- **Preview no es aislado para los tiempos:** `app_settings` es **global**. Un cambio de producción afecta también a Preview; un cambio en el panel Preview no llega a ninguna app.
- **Propagación con caché:** un cambio de búsqueda puede tardar hasta 45 s en reflejarse en la creación de solicitudes (y hasta 10 min en el peor caso de caché).

## Cómo se guardan los valores que acepta Express
- **180 s:** `app_settings.search_timeout_seconds` (global). El cliente lo convierte en `ride_requests.expires_at = creación + 180 s`.
- **20 s:** `app_settings.offer_timeout_seconds` (global). El cliente lo convierte en `driver_offers.expires_at`, que hoy los triggers sustituyen por 30 s. Con v3 se respeta.
- **Aviso flotante de 15 s:** independiente (cierre en `min(vencimiento de oferta, 15 s)`).
