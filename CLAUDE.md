# Express Principal — estado operativo

> Actualizado 2026-10-29. Google Play Producción continúa en `1.6.4+152`. El build `1.6.4+153` está en Internal; no tiene confirmación de QA en teléfono.

## Reglas

- Lee [AGENTS.md](AGENTS.md) y [handoff de GPS/release](docs/GPS_RELEASE_HANDOFF_20261029.md) antes de tocar arquitectura, seguridad, datos o publicación. Confirma GitHub, Supabase y Play antes de afirmar que su estado sigue vigente.
- Conserva los entornos Preview y Producción aislados por la cuenta autenticada. No cambies datos reales, promociones a Producción ni envíes avisos sin autorización expresa.
- La app Android oficial es `com.express.usuario1`, con entrypoint `lib/mobile_main.dart`. No crees una aplicación separada de conductor.

## Release Android

- Producción: `1.6.4+152`, fuente publicada `89f253c42e79942c1d1c6785c7a7297046f75cbe`.
- Internal: `1.6.4+153`, fuente compilada `4a6f04f78c09bf6c8fa53abded37693cfef05337`, basada en la fuente de 152.
- Build 153 limita el aviso persistente de ubicación al conductor. La QA en teléfono aún debe confirmar notificación, movimiento del marcador y reconexión.
- Auditoría 2026-10-29 encontró que el callback `onBroadcast` del pasajero interpreta incorrectamente el evento como `{payload: ...}`. La versión Supabase Dart entrega el mapa del payload directamente. La corrección local consume el mapa recibido, pero no forma parte del build 153 publicado.
- No cambies los archivos ni el SHA de una candidata ya compilada. Cualquier código corregido necesita un nuevo job/versionCode con SHA propio; no reutilices el build 153.

## Web, Supabase y pendientes

- La corrección equivalente del callback web está en el árbol local de trabajo y aún no se ha desplegado. La versión web actualmente servida contiene la lectura anterior.
- La migración `20261028224409_passenger_driver_live_location.sql` está aplicada en Supabase y versionada en esta rama. La función `android-build-worker` desplegada autoriza el flujo exacto del build 153; su fuente se está sincronizando en la rama principal.
- La selección de dirección por pin continúa sin reproducirse ni confirmarse resuelta.
- Adminexpress PR #137 continúa abierto como borrador; la matriz de permisos se guarda, pero faltan acciones de borrado por módulo y zona.
- Separa lo comprobado en CI de lo observado en un teléfono real. No declares resuelto un flujo sin su comprobación correspondiente.
