# Registro web de conductores

El acceso se abre desde el inicio de sesión de la web oficial con **Quiero conducir con Express** o desde `https://expressviajes.online/?registro=conductor`. La cuenta se crea con correo y contraseña (incluye teléfono requerido) o con Google. El callback de Google/correo vuelve a esa misma ruta oficial.

La sesión se valida con el gate de entorno normal antes de abrir el portal. El portal termina de recoger el teléfono si el proveedor OAuth no lo entregó, reutiliza la ficha existente `DriverSetupPage`, sus requisitos por país/zona, las cargas al bucket privado `driver-onboarding` y el RPC `submit_driver_onboarding_v2`. El expediente sigue pendiente de aprobación; la aprobación se hace con el proceso administrativo existente. Tras aprobar, el portal ofrece la ficha de Play para `com.express.usuario1` y el conductor entra con su misma cuenta.

## Correo de aprobación

El código queda preparado en la migración `20261023120000_driver_web_registration_approval_email.sql` y la Edge Function `driver-approval-email`. La migración crea una tabla outbox privada y un trigger que observa la transición de un conductor a `approved`, incluyendo aprobaciones hechas por el panel administrativo. El trigger envía el ID del evento a la función con la clave service role guardada en Vault; la función entrega el correo usando Resend y una clave idempotente por aprobación.

Antes de aplicar la migración o desplegar la función:

1. Guarda en Supabase Vault el secreto `driver_approval_service_role_key` con la service role key del proyecto. No lo escribas en Git ni lo envíes al cliente web.
2. Configura en la función los secretos `RESEND_API_KEY` y `DRIVER_APPROVAL_EMAIL_FROM`. El remitente debe estar verificado por el proveedor.
3. Habilita Google como proveedor de Supabase Auth y añade `https://expressviajes.online/?registro=conductor` a sus URLs de redirección permitidas. El login de Google preexistente sigue usando su redirección actual.

La fuente está en PR #270. La web, la función y la migración no se despliegan ni se aplican automáticamente al incorporar este código. No se envió ningún correo durante su preparación.
