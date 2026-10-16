# Plan de diagnóstico de recepción FCM (sin cambios de producción)

Objetivo: separar, para cada oferta, si el fallo está en el servidor, en FCM, en Android o en la presentación de la app. HTTP 200 de FCM solo confirma aceptación.

## Puntos de observación ya disponibles (sin desplegar nada)
- `notification_delivery_events` (solo lectura): `provider_accepted` por token (`details.token_id`). Permite contar envíos por instalación.
- `native_push_tokens` (solo lectura): `active`, `last_seen_at`, `updated_at`, `floating_offer_enabled`. Sin valores de token.
- Cliente (ya existe): `push_token_registered` con prefijo de 6 caracteres; `card_show` y `overlay_sync` en el registro del conductor.

## Lo que falta para cerrar la causa (requiere decisión)
1. **Confirmar la instalación receptora:** registrar en el cliente un identificador de instalación (no el token) junto a la fila, para saber qué dispositivo tiene cada token. Cambio de cliente y de RPC: requiere autorización.
2. **Recibo en dispositivo:** registrar en el cliente, al recibir un mensaje FCM, `message_id` y si la app estaba en primer plano. Solo registro local, sin enviar datos.
3. **Conteo de tokens activos por usuario** en el envío: métrica para vigilar acumulación. Requiere desplegar la función (no autorizado).

## Criterios
- Un fallo se reporta como "confirmado" solo si hay evidencia en el dispositivo (punto 2) o en el token correcto (punto 1).
- Sin evidencia, se reporta como pendiente.

## Qué no hacer
- No desactivar tokens por HTTP 200 ni por antigüedad.
- No exponer tokens completos en registros ni en GitHub.
