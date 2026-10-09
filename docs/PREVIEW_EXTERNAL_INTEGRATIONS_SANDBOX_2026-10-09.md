# Express Preview — llamadas, pagos y notificaciones independientes
Estado verificado: 2026-10-09. **No aplicar en Producción hasta QA aprobada.**

## Arquitectura y condición de seguridad
- APK QA `com.express.usuario.preview`, Supabase **xbphilqezmwfjfpdbwad**.
- Prod Supabase **zgpijrznvaskgcmauwxx** y APK `com.express.usuario1` nunca reciben pagos, llamadas ni pushes desde Preview.
- El recorrido del viaje ya fue probado por el propietario; falta validar servicios externos con dos cuentas de prueba.

## Lo que se desplegó en Supabase Preview
- `zego-call` (JWT obligatorio): mismo flujo ZEGOCLOUD de Prod para viajes activos; en Preview rechaza `channel=production`.
- `driver-subscription-payments` (JWT obligatorio): flujo de suscripción; Mercado Pago Preview acepta solo un **access token TEST-**. VeriPagos exige `EXPRESS_PREVIEW_VERIPAGOS_SANDBOX_HOST` cuyo host debe coincidir exactamente con el del endpoint de pruebas, o bloquea la llamada antes de `fetch()`.
- `marketplace-payments` (JWT obligatorio): pedidos y Express Plus con test Mercado Pago; bloquea access tokens reales en Preview.
- `express-push-dispatch` (x-express-push-secret para POST): en Preview solo `channel=preview`. Bloquea FCM si el service account JSON no coincide con `EXPRESS_PREVIEW_FIREBASE_PROJECT_ID` y el ID no empieza con `express-preview-`.
- **No** se habilitó `notifications.trg_dispatch_push_notification`: funcionaba en Prod con URL hardcodeada al Supabase Producción y NO se debe copiar tal cual. No se cargaron credenciales externas ni se efectuaron envíos.

## Para completar llamadas reales *entre dos usuarios de prueba*
1. Crear una aplicación ZEGOCLOUD dedicada a QA (no reutilizar la de clientes reales).
2. Configurar únicamente en **Supabase Preview > Edge Function Secrets**: `ZEGO_APP_ID`, `ZEGO_SERVER_SECRET` (32 caracteres), `ZEGO_RESOURCE_ID` (si lo exige invitaciones).
3. Confirmar `zego-call/bootstrap` retorna `configured: true` para cuenta QA; hacer viaje entre dos móviles Preview, llamada, audio, colgar, verificar filas en `private_voice_calls`. No comparte teléfonos personales.
4. Nunca copiar credenciales en GitHub, código, conversación o Producción.

## Para completar notificaciones PUSH
1. Confirmar un proyecto Firebase Preview y la app Android EXACTA `com.express.usuario.preview`.
2. Secret de GitHub Actions: `EXPRESS_PREVIEW_FIREBASE_ANDROID_CONFIG_B64` = **base64 de google-services.json de Preview**. Variable Actions `EXPRESS_PRODUCTION_FIREBASE_PROJECT_ID` debe contener ID Firebase **Producción** (NO el Firebase Preview).
3. En **Supabase Preview > Edge Function Secrets**, poner `FIREBASE_SERVICE_ACCOUNT_JSON` del **mismo Firebase Preview**, y `EXPRESS_PREVIEW_FIREBASE_PROJECT_ID` con el ID exacto del proyecto Preview. No poner service account de Prod.
4. Crear una APK QA a partir del mismo código con `EXPRESS_PREVIEW_PUSH_ENABLED=true`, solo cuando estén verificadas las identidades Firebase y el build fail-closed; las APK anteriores tienen push desactivado por diseño. Comprobar inserción de token QA en `native_push_tokens`, proyecto y canal `preview`.
5. Solo tras validación de cliente + backend, activar el trigger `dispatch_push_notification` **propio de Preview**, apuntando a `https://xbphilqezmwfjfpdbwad.supabase.co/functions/v1/express-push-dispatch`, con secreto Preview de `push_server_config`. **No usar función SQL de Prod:** enviaría a zgpijrznvaskgcmauwxx.
6. Prueba de emisión REAL únicamente a tokens del proyecto Firebase Preview durante viaje QA.

## Para completar pagos
- Efectivo funciona sin pasarela. Simular cobros con sandbox/test de cada operador, nunca enviarlos a cuentas reales.
- Chile Mercado Pago: cargar credenciales TEST de cuenta sandbox SOLO en la configuración de la zona Preview; no usar `APP_USR-` de comercio real. Los endpoints quedarán bloqueados si no hay token TEST-.
- Bolivia VeriPagos: proveedor debe ofrecer URL y claves explícitas de **sandbox**; configurar `EXPRESS_PREVIEW_VERIPAGOS_SANDBOX_HOST` en Supabase Preview y credenciales sandbox de zona; si no hay sandbox, usar pagos de prueba simulados, nunca QR de producción.
- `driver_subscription_settings.provider_enabled` y `driver_subscription_settings.enforce_access` permanecen **false** en Preview hasta tener un proveedor sandbox y tests E2E.
- Los planes adicionales y configuración Marketplace Plus / precios dinámicos deben sembrarse de forma no sensible, asociados a zonas QA con IDs propios. No copiar configuraciones que contengan access tokens ni operaciones reales.

## Auditoría de humo antes de marcar "funciona"
- Todas las funciones anteriores están desplegadas **solo** en Supabase Preview; estar "ACTIVE" **no significa** que haya credenciales sandbox, dispositivos FCM o pruebas completadas.
- Sin keys: llamadas/pagos externos están bloqueados y push no tiene registro de tokens ni trigger. Es estado esperado y seguro.
- Verificar rutas de viaje, rechazo/aprobación, tres estados de pago (pendiente/aprobado/rechazado), audio bidireccional, notificación primer plano/background con dos teléfonos, y que no aparezca ninguna fila/alerta en Producción.
- Promoción a Prod: mismo código validado, migraciones idempotentes revisadas, secretos distintos, sin copiar datos de prueba ni automatizar Play sin autorización explícita.
