# Campeonato Express — implementación web 2026-10-12

## Alcance y navegación

- Nuevo módulo de conductor: **Mi perfil → Campeonato Express**, también accesible desde el menú principal de Conductor. Pantalla independiente con pestañas **Inicio / Top 10 / Premios**.
- Pantalla administrativa: **Admin Express → Campeonato Express**, filtra por ciudad/zona seleccionada y entorno fijo por cuenta. Admin superusuario puede crear o editar nombre, fechas, servicio (todos/Express/Moto/Comfort/XL), estado (borrador/activo/cerrado), tres premios y reglas.
- Predeterminadamente un campeonato es **borrador**. Se muestra al conductor solo cuando `state=active` y las fechas lo incluyen. Los premios son **informativos**, no realizan transferencias ni generan obligaciones automáticas en la billetera.
- Los primeros diez muestran nombres abreviados y viajes completados. El conductor autenticado ve su puesto propio incluso si queda fuera del Top 10. Empates se ordenan por nombre e ID de forma estable.
- Los viajes cancelados, de otras zonas, otros servicios o el otro entorno no suman.

## Backend real

- Tabla `public.driver_championships`, RLS activado, **sin grants de tabla** para cliente. Enlace a `service_zones` y ámbito `(channel,zone_id,service_key)`.
- RPC `driver_championships_for_driver(p_channel)`: requiere login activo, runtime permitido por `resolve_current_runtime_environment`, conductor aprobado con zona activa. Lee `trips.status='completed'`, `trips.completed_at` dentro del campeonato, `trips.channel`, `ride_requests.channel`, `ride_requests.zone_id` y categoría. Ranking computado en base de datos, jamás desde contadores editables por conductor. Sin tráfico en segundo plano; solo abre / actualiza manualmente.
- RPC `admin_driver_championship_list(p_zone_id,p_channel)` y `admin_driver_championship_save(...)`: autorizan administrador en entorno asignado, escritura solo superadministrador, zona permitida, fechas/prizes válidos. Se prohíben campeonatos activos solapados sobre el mismo conjunto de viajes.
- La configuración de servicio `*` incluye todas las categorías elegibles. Cuando hay solapamiento con otra competencia activa se bloquea el guardado, no hay doble recompensa.
- No guardar fotos/teléfonos/IDs de otros conductores en la respuesta de ranking; solo nombre abreviado, puesto y contador. El ID del campeonato y datos propios sí aparecen.
- No modifica `trips`, `ride_requests`, billetera, estados o tarifas, y no dispara pagos.

## Salida y QA
- Sólo **web**, sin nueva APK/AAB ni publicación Google Play. El Android 1.6.1 +139 continúa como artefacto previo, sin incluir esta pantalla.
- Preview permite ensayo con campeonato activo sin mezclar cuentas/datos. Producción no se habilita automáticamente.
- Prueba manual: entrar con conductor aprobado asignado a la ciudad y entorno, abrir Perfil / Campeonato Express, actualizar, comprobar Inicio / Top 10 / Premios, y revisar cifras de viajes. Un conductor no aprobado sólo ve mensaje de acceso no disponible.
- Superadmin: crear en la ciudad correcta, seleccionar servicio, fechas, premios; activar y cerrar; verificar que no puede crear competiciones solapadas ni modificar zonas de otra cuenta.
- La entrega y el pago de premios **quedan manuales** para validación administrativa y eventual módulo de liquidación con auditoría.
- Respaldos GitHub: `backup/before-express-driver-championship-20261012` en Expressdelivery y Adminexpress. PRs y CI web anexados en historial.

## Pendiente de prueba física
- Validación end-to-end de dos conductores reales de la misma zona con viajes completados mientras la campaña está activa; y verificación de reglas de premios y resolución de empates.
