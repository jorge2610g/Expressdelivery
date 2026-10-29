# GPS y release Android — handoff 2026-10-29

## Versiones

- Play Producción sigue en `1.6.4+152`, SHA `89f253c42e79942c1d1c6785c7a7297046f75cbe`.
- Build `1.6.4+153` está en Play Internal. Se compiló desde SHA `4a6f04f78c09bf6c8fa53abded37693cfef05337`, sobre la base exacta de producción 152.
- La QA manual de build 153 está pendiente. No promoverlo a Producción.

## Hallazgo GPS confirmado

La suscripción del mapa del pasajero usa `onBroadcast` de `realtime_client`. Las versiones revisadas de `realtime_client` entregan al callback el mapa del payload directamente. El código que busca `message['payload']` descarta el evento normal de `realtime.send`; por eso el marcador del conductor puede quedarse quieto en el teléfono pasajero.

La rama tiene una corrección local para consumir directamente el mapa del callback. El build 153 publicado no contiene esa corrección y requiere un nuevo job con número de build y SHA propios antes de probarla en Internal. La web tiene la misma corrección preparada en `deploy/web-gps-live`; aún no está desplegada.

La migración `20261028224409_passenger_driver_live_location.sql` ya está aplicada en Supabase. Mantiene el broadcast privado por viaje y acceso limitado a sus participantes. Su archivo fuente se añadió al árbol de trabajo de `deploy/web-gps-live` para conservarlo en `main`. El worker desplegado contiene el permiso limitado para el workflow del build 153; el cambio equivalente está preparado en ese árbol de trabajo para conservar la autorización al desplegarlo después.

## Validación manual pendiente

- En build Internal, comprobar movimiento del marcador del conductor en el teléfono pasajero durante un viaje.
- Confirmar también que el marcador propio del conductor se mueve, que la notificación persistente de ubicación solo aparece al conductor y que la suscripción recupera señal tras perder y recuperar conexión.
- Probar el mismo flujo en web una vez desplegada la corrección.
- La selección de dirección por pin sigue sin reproducirse ni confirmarse resuelta.
- Adminexpress PR #137 permanece en borrador: selección de permisos guardada; acciones de borrado por módulo y zona aún incompletas.

Este documento registra revisión de código. No acredita QA en dispositivo ni despliegue web.
