# Propuesta: higiene de tokens FCM (Preview y Producción)

Estado: **propuesta, no desplegada**. Requiere autorización explícita para aplicar en Supabase y en el cliente.

## Hallazgos (solo lectura, valores enmascarados)

- Cuenta de conductor de auditoría (Preview): 4 tokens activos. Uno corresponde al emulador del conductor (confirmado por registro del dispositivo). Tres son antiguos (última actividad: 9, 12 y 14 de octubre).
- `express-push-dispatch` envía cada oferta a **todos** los tokens activos del usuario en el canal. Cada token antiguo recibió 64 envíos aceptados (HTTP 200) en 24 h.
- FCM devuelve 404/`UNREGISTERED` para instalaciones que ya no existen. Como los tres responden 200, pertenecen a instalaciones todavía registradas en algún dispositivo.

## Causa raíz (confirmada en código)

`public.register_native_push_token_v2` (migración 089) hace `insert ... on conflict(token) do update`. Cuando FCM renueva el token de una instalación, se crea una fila nueva y **la anterior queda `active=true`**. Nada la desactiva. Con el tiempo se acumulan tokens de la misma instalación y cada oferta sale varias veces.

## Qué NO hacer

- No eliminar un token porque FCM responda 200.
- No eliminar un token solo por antigüedad.
- No deduplicar por `device_label`: un conductor puede tener varios dispositivos legítimos.

## Propuesta

1. **Cliente (Flutter):** guardar localmente el último token registrado y enviarlo como `p_previous_token` al registrar el nuevo. Antes de publicarlo, validar que el RPC acepte el parámetro (ver punto 2).
2. **Base de datos (nueva migración, no aplicada):** `register_native_push_token_v3(p_token, p_platform, p_device_label, p_channel, p_previous_token)`. Si `p_previous_token` pertenece al mismo `auth.uid()` y canal, márcalo `active=false` (no lo borra). Mantener el resto de la lógica de v2.
3. **Cierre de sesión:** `unregister_native_push_token` ya existe; verificar que desactiva solo el token propio.
4. **Dispatch:** sin cambios en los criterios de desactivación (solo 404/`UNREGISTERED`). Añadir a los registros el conteo de tokens activos por usuario para vigilar la acumulación.
5. **Limpieza de tokens antiguos existentes:** manual, reversible (`active=false`), solo después de confirmar que ningún dispositivo los usa.

## Pendiente antes de autorizar la limpieza

- Confirmar qué dispositivos tienen instaladas las tres instalaciones antiguas (teléfono personal o cualquier otro AVD con la cuenta de auditoría). Sin esa confirmación no se modifican.

## Plan de pruebas

- Renovar token en el emulador (reinstalar o borrar datos): debe quedar una sola fila activa para esa instalación.
- Envío a conductor con dos dispositivos legítimos: ambos reciben la oferta.
- Cierre de sesión: el token propio queda inactivo.
- Preview y Producción aislados por canal.

## Reversión

Todos los cambios de datos son `active=false`. Reactivar con `update ... set active=true` sobre los identificadores respaldados.
