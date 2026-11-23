# Build 178 · cambios listos y en espera (2026-11-23)

Decisión del propietario: **no se despliega todavía**. Se sigue probando la app y se
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
- La app lee `scheduled_publish_before_minutes` solo si `app_runtime_config` lo devuelve (hoy no): usa 10 por defecto.
  Si el administrador cambia el ajuste, hay que incluirlo en `app_runtime_config` o actualizar el valor por defecto.
- Seguir probando la app: cualquier otro arreglo se suma a esta lista antes de lanzar la 178.

## Cómo seguir

1. Anotar aquí cada arreglo nuevo (commit, qué hace, quién lo ve).
2. Cuando el propietario diga «genera APK»: PR a `main` (con este documento actualizado), subir versión a +178, vigilar la compilación.
