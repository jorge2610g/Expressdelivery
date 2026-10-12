# Express · aumentos rápidos de ofertas por ciudad y servicio (2026-10-12)

## Regla comercial
- Administrador: **Tarifas por zona → Aumentos rápidos del conductor**. Configura tres incrementos ascendentes para **todos los servicios** de una ciudad o para un servicio específico. El servicio específico tiene prioridad.
- Predeterminados sin configuración explícita: Chile/CLP **+250, +500, +750**; Bolivia/BOB **+1, +2, +3**. Son **incrementos**, no importes completos.
- Ejemplo Iquique/Express: solicitud de CLP 1.500 → botones «Aceptar por $1.500», «+$250», «+$500», «+$750». Pulsar +$250 envía una oferta de CLP 1.750 para que el pasajero confirme.
- Por defecto no cambia la tarifa del pasajero sin aceptación. «Otro monto» sigue disponible.

## Fuente de verdad
- Una migración crea `driver_quick_offer_rules` con clave primaria `(channel,zone_id,service_key)`, `service_key='*'` para valor de ciudad; RLS y sin permisos de tabla a clientes. Cuenta Preview y Producción tienen configuraciones distintas.
- `admin_driver_quick_offer_get/set`: protegidos por `is_admin`, `admin_environment_allowed`, superadmin para escritura y zona asignada. Se valida que los 3 números sean positivos, crecientes y múltiplos del redondeo monetario configurado para esa moneda.
- `available_ride_requests_for_driver_v4` reutiliza la autorización y el despacho de v3, añade `quick_offer_steps` a cada solicitud del conductor en la **misma llamada**. No se introduce un nuevo polling de configuración.
- Flutter muestra estos tres pasos al recibir la solicitud. Si un backend antiguo todavía responde con v3, usa los valores predeterminados por moneda.
- `createRideOffer` deja de rechazar montos normales CLP por el límite legacy global de 9999, manteniendo la restricción anterior para BOB. El trigger de ofertas persistidas conserva el redondeo de tarifa que quedó congelado en la solicitud del pasajero.
- No altera tarifas, comisiones, ganancias ni ofertas anteriores.

## Despliegue y pruebas
- Proyecto Supabase oficial: `zgpijrznvaskgcmauwxx`, migración versionada en Expressdelivery `20261012160500_driver_quick_offer_zone_service.sql`.
- Una sola web: `expressviajes.online`, un solo Adminexpress: `admin.expressviajes.online`. Las cuentas fijan Preview o Producción.
- Respaldo: `backup/before-driver-quick-offers-by-zone-service-20261012` en ambos repositorios.
- QA: admin de Preview configura Iquique todos los servicios +250/500/750; sobrescribe Moto +100/200/300; confirmar que Express hereda 250/500/750 y Moto muestra 100/200/300. Otra ciudad no cambia. Bolivia por defecto +1/2/3. Confirmar total de oferta y monto aceptado del pasajero, viaje final, ganancias del conductor.
- Validar que admin Producción no puede leer/escribir Preview y viceversa; monitor de zona no puede cambiar valores; solicitudes de otro entorno no se exponen. Revisar valores con CLP >9999 y sin montos decimales inadvertidos.
- Cambio de reglas afecta solicitudes mostradas nuevamente en el cliente, sin reescribir ofertas ya enviadas ni viajes completados. No publicar APK/AAB Android; compartir Dart y validar web primero.
