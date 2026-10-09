# Express — separación real de Supabase y notificaciones (2026-10-08)

**Estado:** cambios de aplicación preparados en rama, sin desplegar ni certificar. No se han cambiado ni Production Supabase ni Google Play.

## Regla permanente: mismo código, datos y servicios aislados

- **Supabase Production:** `zgpijrznvaskgcmauwxx` — Canadá (`ca-central-1`). Datos reales. No se modifica durante estas pruebas.
- **Supabase Preview:** `xbphilqezmwfjfpdbwad` — Canadá (`ca-central-1`). Base con la misma estructura funcional, pero cuentas, documentos, viajes, tokens y claves independientes.
- **Un solo código:** `lib/mobile_main.dart` y lógica Flutter compartida, compilado con `EXPRESS_PREVIEW_MODE=true` para Preview y `false` para Producción. `lib/core/supabase_client.dart` selecciona URL **y publishable key** de cada Supabase sin fallback de Preview a Producción.
- **Paquetes Android:** Preview `com.express.usuario.preview` (o QA temporal `com.express.usuario.qa`), Producción `com.express.usuario1`. La publicación a Play es un circuito aparte.
- Queda prohibido cambiar una sesión o cuenta a un canal diferente desde el mismo proyecto. Un candidato Android Producción NO puede acceder a cuentas Preview por el antiguo `resolve_current_runtime_environment`.
- Promocionar **los mismos archivos, SHA, migraciones y fuente Edge** aprobados; cambiar únicamente secretos, referencias de proyecto y parámetros explícitos de entorno. No copiar usuarios ni sobreescribir datos en Production.

## Push Android: bloqueado por defecto en Preview hasta FCM independiente

**Production:** continúa usando su Firebase/FCM actual.

**Preview:** antes de activar Push, crear/configurar un **proyecto Firebase diferente**, con credenciales, sender ID, service account, app ID y aplicación Android exclusivos de Preview.

`lib/push_notifications_native.dart` rechaza cargar Firebase en Preview salvo que:
1. `EXPRESS_PREVIEW_FIREBASE_PROJECT_ID` esté explícitamente definido.
2. `EXPRESS_PRODUCTION_FIREBASE_PROJECT_ID` esté explícitamente definido.
3. Ambos IDs de Firebase sean distintos.
4. El `FirebaseOptions.projectId` cargado en tiempo de ejecución sea el Preview esperado.

Si falta cualquiera de esos requisitos, **no se registra ningún token nuevo de Preview ni se inicializa FCM desde esta ruta**. El resto de la app puede iniciar; Push se considera no disponible, no se reemplaza con credenciales de Producción. No declarar Push Preview operativo hasta ejecutar recepción y envío reales con usuarios de prueba y comprobar ausencia de destinatarios de Production.

Nunca copiar `FIREBASE_SERVICE_ACCOUNT_JSON`, claves privadas, tokens, VAPID ni secretos de Producción al proyecto Preview. Secretos se configuran únicamente en su propio Supabase.

## Web Push / PWA

`web/index.html` resuelve el destino de Push desde el emisor (`iss`) del JWT de la sesión; jamás presupone Producción para un JWT Preview o desconocido.

**Web Push Preview permanece desactivado por diseño**, hasta disponer de un origen de pruebas separado, un registro de service worker con scope aislado y un par VAPID exclusivo. Compartir el mismo dominio y service worker de Producción podría desuscribir a usuarios reales al alternar pruebas. Los tokens Preview jamás deben llamar al endpoint Push de Production.

## Base de datos, Edge Functions y otros proveedores

La copia principal de Preview ya conserva esquemas, tablas, índices, claves y políticas RLS. Hay funciones SQL y disparadores pendientes de paridad, y las Edge Functions siguen sin desplegarse en Preview. **No copiar las 18 Edge Functions de Production a ciegas**: examinar cada dependencia a servicios externos, webhook, pagos, firma y push. Enviar correos, SMS, cargos o notificaciones reales desde Preview queda prohibido.

Punto crítico encontrado en migraciones históricas: `014_dispatch_notifications_to_web_push.sql` y `053_zone_safe_push_deeplinks.sql` contienen una URL hardcodeada de **Supabase Production** en `dispatch_push_notification()`. Preview **no** debe instalar ese disparador sin reemplazarlo por una implementación de código compartido con destino configurado por proyecto y validación fail-closed; mientras tanto, el disparador de envío se mantiene ausente y los envíos Preview apagados. No cambiar el disparador activo de Producción durante esta preparación.

Antes de activar módulos externos en Preview, validar también:
- Pagos y suscripciones (solo credenciales/sandbox Preview; sin cobros reales).
- SMS / OTP / Didit (desactivados por decisión de producto, en ambos entornos).
- ZEGOCLOUD y llamadas privadas (identificadores/credenciales y participantes de prueba, sin cruzar sesiones).
- Analytics, logs, storage, OAuth/redirect URLs y backups separados.
- Panel Admin Express (credenciales del proyecto y permisos distintos; nunca usar service role en cliente).
- Workers de Android/GitHub (no despachar eventos Preview a URLs o tablas Production).

## Pruebas bloqueantes antes de dar Preview por listo

1. Compilar el mismo código con `--dart-define=EXPRESS_PREVIEW_MODE=true` y `false`; comprobar URLs y proyectos inequívocos en ambos modos.
2. Registrar dos usuarios de prueba solo en Preview y verificar que Production conserva usuarios/datos.
3. Comprobar que token/JWT, storage y RLS de Preview no autorizan escritura ni lectura en Production.
4. Comprobar que **Push Preview** no envía nada cuando falta un secreto o la configuración FCM es incorrecta, y que los tokens de cada Firebase están separados cuando se active.
5. Probar notificación pasajero/conductor dentro de Preview; confirmar los destinatarios y que ningún usuario real de Production reciba nada.
6. Probar flujos de registro manual, aprobación, cambio de teléfono, solicitud/viaje, moneda por zona y panel Admin en Preview.
7. Verificar Edge Functions, migraciones e integraciones, comparar por SHA y evitar cualquier promoción de datos.
8. Certificar el SHA aprobado y promocionar únicamente código, funciones y migraciones compatibles preservando Production.

**Pendiente**: paridad final de SQL/Edge Functions, Firebase/VAPID/origen separados, cableado Admin Express, builds y QA real. **No lanzar Push Preview ni declarar separación integral certificada antes de completar esas pruebas.**
