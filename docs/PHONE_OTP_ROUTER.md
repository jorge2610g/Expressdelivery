# Phone OTP Router · Express 1.5.99+144

## Objetivo

Verificar exclusivamente el número de teléfono de pasajeros y conductores sin usar SMS para estados del viaje. Los estados del viaje continúan por push.

## Enrutamiento

1. El backend resuelve el proyecto Firebase correspondiente al entorno.
2. Reserva de forma atómica hasta 10 envíos Firebase por día y por `projectId`.
3. Mientras haya cupo, la app usa Firebase Phone Auth.
4. Cuando se agota el cupo:
   - Chile (+56) -> LETEL.
   - Bolivia (+591) -> Unimatrix.
5. Si el proveedor secundario todavía no tiene credenciales, el backend se detiene y NO continúa enviando por Firebase de pago.

El contador está del lado servidor. El APK no puede modificarlo.

## Seguridad

- Edge Function: `phone-otp`, JWT Supabase obligatorio.
- Las claves LETEL/Unimatrix nunca están en Flutter ni en Git.
- Tablas `phone_otp_provider_usage` y `phone_otp_challenges` tienen RLS y no tienen políticas de cliente.
- Reenvío: mínimo 60 segundos.
- Límite: 20 solicitudes/24h por usuario y 10/24h por número.
- Desafío Firebase: máximo 10 minutos.
- OTP externo: 5 minutos.
- Máximo 5 intentos por desafío.
- El backend valida que el número confirmado por Firebase sea exactamente el mismo número solicitado.
- Cambiar el número sigue invalidando `phone_verified_at`.

## Firebase

Flutter usa `firebase_auth`. La app ya inicializa Firebase mediante la infraestructura de push existente.

Antes de probar en un dispositivo real:

1. Firebase Console -> Authentication -> Sign-in method -> Phone -> Enable.
2. Registrar SHA-1 y SHA-256 de la firma Android correspondiente.
3. Confirmar que existen las apps Android:
   - Preview: `com.express.usuario.preview`
   - Producción: `com.express.usuario1`
4. Phone Auth requiere un dispositivo real para la prueba completa.

La incorporación de `firebase_auth` es dependencia nativa. Por eso 1.5.99+144 requiere una nueva base Preview; no es un cambio apto para aplicar solamente con Shorebird sobre una base que no tenga ese plugin.

## LETEL · Chile

Adaptador incluido y desactivado hasta cargar secretos.

Endpoint por defecto:
`POST https://api.letel.cl/v1/sms/send`

Secretos:

- `LETEL_API_KEY`
- `LETEL_API_URL` opcional
- `LETEL_SENDER_ID` opcional, default `EXPRESS`
- `PHONE_OTP_PEPPER` obligatorio para validar OTP generado por Express

Mensaje corto ASCII para evitar segmentos UCS-2:
`Express: tu codigo de verificacion es 123456. Vence en 5 min.`

## Unimatrix · Bolivia

Adaptador OTP nativo incluido y desactivado hasta cargar secretos.

Acciones:
- `otp.send`
- `otp.verify`

Secretos:

- `UNIMTX_ACCESS_KEY_ID`
- `UNIMTX_ACCESS_KEY_SECRET` recomendado para HMAC
- `UNIMTX_API_URL` opcional, default `https://api.unimtx.com/`

Intent fijo: `express_phone_verify`.
Canal: `sms`.
TTL: 300 segundos.

## Switches de AdminExpress

Los switches existentes siguen siendo independientes:

- `sms_verification_passenger_enabled`
- `sms_verification_driver_enabled`

No se activan automáticamente con esta implementación.

En Preview se pueden habilitar para probar.
Producción debe mantenerse apagada hasta certificar Preview y realizar una verificación real del proveedor.

## QA mínimo

1. Compilar una nueva base Preview 1.5.99+144 cuando el usuario lo ordene.
2. Activar Phone Auth en Firebase y registrar SHA.
3. Encender solo el switch SMS de Preview que se quiera probar.
4. Solicitar OTP.
5. En Preview debe mostrar `Proveedor OTP: Firebase`.
6. Ingresar el código correcto.
7. Confirmar `public.users.phone`, `phone_country_code` y `phone_verified_at`.
8. Probar código incorrecto y expirado.
9. Probar reenvío antes de 60 s.
10. Mantener Producción sin exigir OTP hasta certificación.

## Estado de despliegue backend

- Migración aplicada: `phone_otp_multi_provider_router`.
- Edge Function `phone-otp` desplegada.
- LETEL y Unimatrix esperan credenciales.
- No se ha generado APK/AAB automáticamente.
