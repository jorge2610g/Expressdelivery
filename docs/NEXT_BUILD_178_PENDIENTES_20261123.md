# Build 178 · registro histórico (2026-11-23)

> **Estado actualizado 2026-11-25:** la build 178 ya está lista en Google Play Internal; fue compilada desde `c3d884fe610699315e358f2676d6eed33eea68da` y no contiene los cambios de banners de los PR #519 y #520. `main` está en `ac84419878a60de54cb3f631e1a3ac291fc5f217`, QA web pasó y la siguiente build disponible es `1.6.9+179`. El propietario ordenó generarla para Prueba interna; `pubspec.yaml` y `.github/build-requests/android-internal.json` ya apuntan a +179 en la rama de release. Solo Internal, sin promoción a Producción; QA en dispositivo queda pendiente.

Este documento conserva el historial y las decisiones originales de la 178. Los cambios nuevos que entrarán en la 179 son el carrusel de banners de pasajero con imágenes/videos, enlaces por banner, tamaños por ubicación y ajuste de encuadre.

Decisión del propietario (2026-11-23): lanzar la build 178 (ya ordenada). Antes: en espera. Se sigue probando la app y se
juntan los arreglos para lanzar **una sola build** (no cambiar de build a cada rato).
Nada de esto está en `main` ni en Play; todo está en la rama `claude/cool-faraday-yhh09s`.

Estado de Play al escribir esto: Prueba interna **1.6.9+177** (lista, firma de producción).
Producción de Play: sin promoción autorizada. `app_release_gate`: siguiente número **178**.

## Ya hecho en la rama (código de la app) — falta fusionar y generar APK

| Commit | Qué hace | Quién lo ve |
| --- | --- | --- |
| `c6040655` / `6833f0b5` | App del conductor: se refresca al llegar avisos del viaje (`trip_status`, `trip_completed`, `trip_cancelled`, `ride_cancelled`, `ride_assigned`) y cada 6 s mientras tiene un viaje en curso (`_refreshDriverActiveTripIfNeeded`, separado del refresco de emergencia). | Conductor |
| `3ac8ebc1` | App del pasajero: «Viaje programado» se muestra hasta 10 min antes de la hora (`expressScheduledPublishLeadMinutes`, antes fijo en 30) y el texto dice cuándo recibirán el viaje los conductores. | Pasajero |

Para lanzar: fusionar un PR de la rama a `main` y subir `pubspec.yaml` a `1.6.9+178` junto con
`.github/build-requests/android-internal.json` (build 178 + changelog). Solo con la orden «genera APK».

## Ya activo en Supabase (no requiere build)

Aplicadas el 2026-11-23, con pruebas en transacciones revertidas:

- `admin_trip_actions_notify_driver_live` (`20261123320000`): las acciones de soporte del panel
  (iniciar, completar, cancelar, liberar, reasignar) tocan la solicitud (refresco inmediato del
  conductor, también con versiones ya instaladas) y «Iniciar viaje» avisa al conductor.
- `scheduled_rides_publish_on_time` (`20261123330000`): viajes programados salen a los conductores
  10 min antes (`app_settings.scheduled_publish_before_minutes = 10`, mínimo 5); trabajo
  `publish-due-scheduled-rides` cada minuto; `ride_requests.scheduled_published_at`.
- Anteriores del día: precio fijo de 3 minutos y 30 s por conductor, conductores ya no se
  desconectan solos por falta de ubicación (el despacho exige ubicación de menos de 3 min),
  integridad de viajes y sanciones, ranking y viajes del campeonato en el panel.

Los archivos de las migraciones `20261123320000` y `20261123330000` están en la rama, no en `main`.

## Pendiente de verificar con el propietario antes de lanzar

- Anticipación de los programados: 10 min (propuesta). El mínimo al programar en la app es 15 min.
- Anticipación configurable (verificado 2026-11-23): el panel ya tiene el campo «Publicar viaje programado antes · minutos» (ajustes avanzados, rango 5–1440, hoy 10). El servidor lo usa en `publish_due_scheduled_rides` y `app_runtime_config` devuelve toda la fila `app_settings`, así que la app (build 178) lo lee y lo aplica sin otra build. Las versiones anteriores a la 178 siguen mostrando 30 min fijo.
- Seguir probando la app: cualquier otro arreglo se suma a esta lista antes de lanzar la 178.

## Cómo seguir

1. Anotar aquí cada arreglo nuevo (commit, qué hace, quién lo ve).
2. Cuando el propietario diga «genera APK»: PR a `main` (con este documento actualizado), subir versión a +178, vigilar la compilación.

## Chat: avisos al teléfono (2026-11-24, servidor, ya activo)

- `service_message_notification_channel` (`20261124000000`): los avisos de chat salían siempre por «production» porque no llevaban `trip_id`/`delivery_id`; las cuentas de Prueba tienen sus teléfonos registrados en «preview» y no recibían el aviso. Ahora el canal sale del viaje. Probado en transacción revertida (viaje de Prueba → preview; Producción → production). No requiere build.
- Pendiente (no tocado): `express-push-dispatch` envía `service_message` con prioridad normal (puede llegar tarde con el teléfono dormido); añadirlo a `urgentTypes` si siguen los retrasos.
- Una cuenta de Producción tenía su token del teléfono desactivado (FCM 404) desde las 19:04 del 23-11; la app lo renueva al abrirse.
