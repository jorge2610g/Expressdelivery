# Express Web · control de portada por zona y entorno (2026-10-13)

## Contrato del propietario
- La misma versión de Express Web contiene Viajes, Envíos y Market en Preview y Producción.
- Admin Express decide los servicios visibles y el modo de apertura por zona.
- Las cuentas Preview leen `admin_environment_config` de su zona; las de Producción leen `service_zones`. No se mezclan pedidos, viajes, tarifas ni cuentas.
- Market respeta su habilitación comercial independiente para Preview y Producción, y la visibilidad de comercios en el canal de la cuenta.
- El modo `always` muestra la portada aun con un solo servicio disponible; `auto` la muestra con más de uno; `direct` abre el predeterminado.
- Al abrir Express Web se consulta nuevamente la configuración de zona en segundo plano; se conserva una vista inicial rápida desde la caché, pero la caché no es una autorización permanente.
- La publicación Web no crea APK ni activa Market en Producción.

## Comprobación antes de fusionar y desplegar
1. En Adminexpress con cuenta Preview, editar la misma zona y marcar solo Viajes y Market; establecer `always` y guardar.
2. Con pasajero Preview dentro de esa zona, abrir `https://expressviajes.online/` y verificar dos tarjetas, sin Envíos. Reiniciar web y comprobar el mismo resultado.
3. Cambiar desde Admin a solo Viajes, guardar y reabrir Web: la portada debe reflejar el cambio.
4. Entrar con pasajero Producción en la misma zona: verificar que no hereda las selecciones de Preview y que mantiene el flujo de Taxi.
5. Comprobar que el usuario no puede cambiar de canal solicitando `p_channel=preview` desde una cuenta Producción.
6. Validar pruebas de Flutter, build oficial de Web, migración SQL y HTTPS con marcador de versión.
