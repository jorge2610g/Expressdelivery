# Registro web independiente de conductores

## Acceso público

El formulario se abre directamente con este enlace, que también puede imprimirse como QR:

`https://expressviajes.online/?registro=conductor`

No hay un botón para conducir en la página de inicio ni en el acceso web habitual. En esta ruta, la persona crea una cuenta con correo y contraseña o continúa con Google; si ya tiene cuenta, puede iniciar sesión para revisar o completar el expediente. Ambos métodos regresan a la misma página y usan el mismo usuario que la aplicación Express.

## Alcance del portal

La página de registro sirve únicamente para completar el expediente y seguir su aprobación. En la web oficial de viajes, todas las cuentas usan el shell de pasajero: no se muestra el cambio a modo conductor ni se procesan eventos que abran herramientas de conductor. Android conserva su selector de modo y todas sus funciones. El portal directo de registro no monta el mapa ni funciones de viaje o conductor.

El formulario reutiliza los requisitos actuales de `DriverSetupPage`, el almacenamiento privado de documentos y el expediente de onboarding existente. La ubicación se consulta una vez para sugerir país y ciudad del registro. Si la persona niega el permiso o no hay ubicación disponible, puede elegir país y ciudad manualmente. La web no sigue ni usa su ubicación para viajes.

El estado se comparte con la aplicación mediante la misma cuenta y el mismo registro del backend. Después de enviar el formulario, la web abre la pantalla existente **Vehículo y documentos**, con el mismo resumen de país/zona, identidad, foto de perfil, vehículo y documentos adicionales. Esa pantalla permanece abierta mientras se revisa. Como los cambios de cada documento no están publicados en Realtime, el modo web vuelve a consultar el expediente cada cinco segundos y también usa los eventos de perfil/notificación existentes. Las acciones de corrección reutilizan el mismo formulario de siempre.

Cuando el perfil queda aprobado, el resumen se cierra y el portal muestra **¡Bienvenido a Express!**, la confirmación de aprobación y el botón **Descargar app** hacia Play Store. Indica iniciar sesión con las credenciales del registro. La pantalla también orienta a recuperar la contraseña desde el enlace existente **¿Olvidaste tu contraseña?** del acceso compartido. El portal nunca habilita viajes desde la web.

## Correo de aprobación

La migración `20261023120000_driver_web_registration_approval_email.sql` y la Edge Function `driver-approval-email` preparan un aviso de aprobación para el mismo expediente, incluso si la aprobación se hace desde el panel.

Antes de activarlas:

1. Guarda en Supabase Vault el secreto `driver_approval_service_role_key`. No lo escribas en Git ni lo envíes al navegador.
2. Configura en la función `RESEND_API_KEY` y `DRIVER_APPROVAL_EMAIL_FROM`, con remitente verificado.
3. Añade la redirección exacta de autenticación `https://expressviajes.online/?registro=conductor` a la lista permitida de Supabase Auth.

La nueva migración `20261023131500_driver_web_onboarding_manual_zone.sql` valida servidor a servidor que el país y la ciudad tengan habilitado el registro. Si se recibió ubicación, verifica que corresponda a esa ciudad; si no, acepta la selección manual. Conserva las validaciones existentes de documentos, servicios y archivos privados.

El código está en PR #270. La migración `driver_web_onboarding_manual_zone_20261023131500` ya se aplicó en Supabase Production; una verificación de solo lectura confirmó la función `submit_driver_web_onboarding`, su `search_path` vacío y ejecución concedida solo a `authenticated` y `service_role`. La web oficial sigue sin desplegarse y muestra la versión anterior. La migración de correo y la Edge Function no están activas: falta `driver_approval_service_role_key` en Vault y la autorización específica para enviar el nombre y correo del conductor a Resend. No se hizo ninguna solicitud de registro ni se modificaron datos de usuarios.
