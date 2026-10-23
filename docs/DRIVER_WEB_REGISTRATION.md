# Registro web independiente de conductores

## Acceso público

El formulario se abre directamente con este enlace, que también puede imprimirse como QR:

`https://expressviajes.online/?registro=conductor`

No hay un botón para conducir en la página de inicio ni en el acceso web habitual. En esta ruta, la persona crea una cuenta con correo y contraseña o continúa con Google; si ya tiene cuenta, puede iniciar sesión para revisar o completar el expediente. Ambos métodos regresan a la misma página y usan el mismo usuario que la aplicación Express.

## Alcance del portal

La página sirve únicamente para registrar y seguir la aprobación. No monta el mapa, el panel de pasajero ni funciones de viaje o conductor.

El formulario reutiliza los requisitos actuales de `DriverSetupPage`, el almacenamiento privado de documentos y el expediente de onboarding existente. La ubicación se consulta una vez para sugerir país y ciudad del registro. Si la persona niega el permiso o no hay ubicación disponible, puede elegir país y ciudad manualmente. La web no sigue ni usa su ubicación para viajes.

El estado se comparte con la aplicación mediante la misma cuenta y el mismo registro del backend. Mientras está pendiente, la persona puede consultar el estado desde la web o desde su perfil en la app. Si un documento requiere corrección, puede reemplazarlo desde cualquiera de los dos flujos. Al aprobarse, esta página solo muestra la confirmación y el enlace de descarga de la aplicación oficial `com.express.usuario1`; no habilita viajes desde la web.

## Correo de aprobación

La migración `20261023120000_driver_web_registration_approval_email.sql` y la Edge Function `driver-approval-email` preparan un aviso de aprobación para el mismo expediente, incluso si la aprobación se hace desde el panel.

Antes de activarlas:

1. Guarda en Supabase Vault el secreto `driver_approval_service_role_key`. No lo escribas en Git ni lo envíes al navegador.
2. Configura en la función `RESEND_API_KEY` y `DRIVER_APPROVAL_EMAIL_FROM`, con remitente verificado.
3. Añade la redirección exacta de autenticación `https://expressviajes.online/?registro=conductor` a la lista permitida de Supabase Auth.

La nueva migración `20261023131500_driver_web_onboarding_manual_zone.sql` valida servidor a servidor que el país y la ciudad tengan habilitado el registro. Si se recibió ubicación, verifica que corresponda a esa ciudad; si no, acepta la selección manual. Conserva las validaciones existentes de documentos, servicios y archivos privados.

El código está en PR #270. La web oficial, la migración de onboarding, la migración del correo y la Edge Function no se han desplegado ni aplicado desde esta preparación.
