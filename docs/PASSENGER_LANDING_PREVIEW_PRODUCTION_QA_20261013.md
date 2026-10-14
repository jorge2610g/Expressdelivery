## Actualización 2026-10-14 · Inicio automático sin controles redundantes

- La decisión de apertura depende **únicamente** de cuántos módulos permite la zona para esa cuenta: uno directo, dos o tres en portada, cero indisponible. Los valores antiguos `always`/`direct` ya no pueden alterar el resultado.
- Admin Express dispone de una sola sección por zona para la selección de Viajes, Envíos y Market. Esa selección sincroniza `zone_service_catalog` para Taxi/paquetería sin cambiar permisos de conductores ni tarifas.
- Envíos solo aparece como operativo con **ambas** claves `parcel` y `delivery`, visibles en el canal. Se respeta la autorización Preview por identidad, no el parámetro editable de solicitud.
- Para Preview, `app_zone_context_v3` toma servicios efectivos de `zone_services` de la sombra QA. Production conserva sus tablas operativas.
- Una migración normaliza los órdenes antiguos de Producción antes de activar Market en una zona para que no quede visible accidentalmente en otras.

---

# Express Web · control de portada por zona y entorno (2026-10-13)

## Contrato del propietario
- La misma versión de Express Web contiene Viajes, Envíos y Market en Preview y Producción.
- Admin Express decide los servicios visibles y el modo de apertura por zona.
- Las cuentas Preview leen `admin_environment_config` de su zona; las de Producción leen `service_zones`. No se mezclan pedidos, viajes, tarifas ni cuentas.
- Market respeta su habilitación comercial independiente para Preview y Producción, y la visibilidad de comercios en el canal de la cuenta.
- Independientemente del modo histórico, con 1 módulo abre ese servicio, con 2 o 3 módulos muestra la portada y con 0 la zona aparece sin servicios.
- Al abrir Express Web se consulta nuevamente la configuración de zona en segundo plano; se conserva una vista inicial rápida desde la caché, pero la caché no es una autorización permanente.
- La publicación Web no crea APK ni activa Market en Producción.

## Comprobación antes de fusionar y desplegar
1. En Adminexpress con cuenta Preview, editar la misma zona y marcar solo Viajes y Market; establecer `always` y guardar.
2. Con pasajero Preview dentro de esa zona, abrir `https://expressviajes.online/` y verificar dos tarjetas, sin Envíos. Reiniciar web y comprobar el mismo resultado.
3. Cambiar desde Admin a solo Viajes, guardar y reabrir Web: la portada debe reflejar el cambio.
4. Entrar con pasajero Producción en la misma zona: verificar que no hereda las selecciones de Preview y que mantiene el flujo de Taxi.
5. Comprobar que el usuario no puede cambiar de canal solicitando `p_channel=preview` desde una cuenta Producción.
6. Validar pruebas de Flutter, build oficial de Web, migración SQL y HTTPS con marcador de versión.

## Criterio de publicación
El mismo commit y el mismo bundle Web se sirven a ambos contextos. La diferencia de visibilidad debe depender exclusivamente de la configuración guardada por Adminexpress para el canal y la zona de la cuenta, junto con los permisos comerciales de ese módulo. Nunca se fuerza el contexto Preview mediante parámetros editables del navegador.
