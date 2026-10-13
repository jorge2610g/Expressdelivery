# Envíos y Paquetería · validación web por cuenta (2026-10-13)

## Comportamiento correcto
- Una sola web oficial y una sola base de código para ambas modalidades.
- Taxi se gestiona con solicitudes de viaje; Envíos se gestiona con `delivery_requests`, repartidor, chat, seguimiento e historial. No debe generarse un `ride_request` al pulsar Envíos.
- La tarjeta exige **dos permisos**: estar seleccionada en «Pantalla inicial» y existir un servicio Delivery disponible y visible en la **zona y canal**.
- La configuración `zone_services` de Preview es separada y solo visible para cuentas QA autenticadas; la Producción continúa usando `zone_service_catalog`. El parámetro enviado por el cliente no autoriza Preview.
- Envíos abre un formulario propio con recogida y entrega geolocalizadas, tipo de paquete, tarifa propuesta y pago en efectivo. Sin coordenadas y sin importe válido no envía la solicitud. Después de crearla, abre el seguimiento de la entrega.
- La tarifa y moneda se determinan y verifican en el backend de acuerdo con la zona, sin importe ficticio fijo.
- Los repartidores deben ser de la misma zona y contexto; Producción continúa con Envíos desactivado hasta activación explícita.

## Pruebas mínimas de aceptación
1. Con Adminexpress Preview, seleccionar Iquique, activar Delivery en «Servicios» para pasajero y conductor, y marcar solo Taxi y Envíos en la portada, modo «Mostrar siempre».
2. Con pasajero Preview de Iquique, abrir Express Web: se muestran exactamente Taxi y Envíos. Tras recargar se conserva la selección.
3. Pulsar Envíos: verificar **Nuevo envío**, selector de recogida y entrega, tipo de paquete, importe y botón «Buscar repartidor». No mostrar CTA de viaje.
4. Crear un envío ficticio únicamente con identidades y coordenadas QA; verificar el registro en `delivery_requests` canal Preview (no `ride_requests`) y que el repartidor Preview de Iquique recibe la solicitud.
5. Verificar progreso de búsqueda/asignación/historial/cancelación; rechazar cruces de zona y de canal. Cualquier fallo bloquea la promoción operativa.
6. Con pasajero Producción de Iquique, la entrada continúa directa a Taxi; `zone_service_catalog.delivery` permanece deshabilitado. No crear viajes ni pedidos reales.
7. Validar Flutter analyze/test/build Web y despliegue canónico. APK solo bajo orden expresa.
