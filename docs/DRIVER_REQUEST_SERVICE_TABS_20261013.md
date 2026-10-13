# Filtros de solicitudes por permiso (2026-10-13)

La interfaz y el aviso emergente actuales de Taxi no cambian para un conductor con un solo permiso Taxi.
Al abrir **Solicitudes activas**, la app consulta `my_driver_work_permissions` para su identidad y entorno.
- Un solo servicio aprobado: sin pestañas adicionales.
- Dos o tres servicios aprobados: pestañas **Taxi**, **Envíos**, **Delivery** (solo las autorizadas).
- Taxi usa `ride_requests`; Paquetería usa `delivery_requests` sin `marketplace_order_id`; Delivery comercial usa solicitudes con `marketplace_order_id`.
- Las tarjetas muestran detalles, sin botones de aceptar ni rechazar; al tocar Taxi reabre su popup existente. Al tocar un reparto se abre un diálogo de confirmación, no se acepta desde la lista.
- La tabla y RPC de permisos independientes deben estar instaladas, y Adminexpress debe permitir su aprobación. Si todavía falta la migración, la interfaz cae de forma segura al modo Taxi anterior. **No se deben inferir autorizaciones a partir del tipo de vehículo.**
- Sin migración aprobada y sin permisos administrativos no hay forma segura de verificar las pestañas múltiples con cuentas reales. El aviso automático de 30 segundos para los dos tipos de entrega y la negociación tipo Taxi de Paquetería siguen pendientes: este cambio NO los implementa.
- No modifica tarifa, asignación, autorización del servidor, catálogo de zona o flags de producción; no genera APK.

QA requerida antes de fusionar: compilar Flutter Web, ejecutar prueba `driver_service_requests_sheet_test.dart`, verificar cuenta únicamente Taxi sin cambios; en entorno Preview autorizado probar Taxi+Envíos y Taxi+Envíos+Delivery, abrir cada lista, validar popup y bloqueo en servicio ocupado.
