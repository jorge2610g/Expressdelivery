# Google Play submission checklist — Express

Actualizado: 2026-10-01

Candidato de validación actual: **Express 1.5.72 · build 113**.

Este documento refleja el comportamiento real del repositorio y debe mantenerse sincronizado con Play Console.

## Identidad del paquete

- App: Express
- Android applicationId: `com.express.usuario1`
- Artefacto para Play: Android App Bundle (.aab)
- Target SDK obligatorio: 36
- Firma: keystore de producción persistente
- Correo de soporte/privacidad: soporte@expressdelivery.pro

## URLs públicas

- Política de privacidad: https://expressviajes.online/privacidad/
- Eliminación de cuenta: https://expressviajes.online/eliminar-cuenta/
- Términos: https://expressviajes.online/terminos/

## App content / acceso del revisor

Express requiere inicio de sesión para revisar el flujo completo.

Antes de enviar a revisión:
1. Crear una cuenta de revisor permanente de tipo pasajero.
2. Crear una cuenta de revisor permanente de tipo conductor aprobada.
3. No exigir OTP temporal, ubicación geográfica especial ni enlace que expire para esas cuentas.
4. Colocar usuario/contraseña e instrucciones en **Policy > App content > App access**.
5. Explicar que una misma aplicación contiene modo Pasajero y modo Conductor.

No guardar contraseñas de revisión en este repositorio.

## Data Safety — datos recogidos

Declarar como **recogidos** cuando se transmiten al backend:

### Ubicación
- Ubicación aproximada: Sí.
- Ubicación precisa: Sí.
- Fines: funcionalidad de la app, seguridad/prevención de fraude.
- La ubicación precisa se usa para origen/destino, conductores cercanos, viaje activo y SOS.
- No se solicita `ACCESS_BACKGROUND_LOCATION`.
- El conductor online/viaje activo puede usar un servicio en primer plano visible.

### Información personal
- Nombre: Sí.
- Correo electrónico: Sí.
- Número de teléfono: Sí.
- ID de usuario: Sí.
- Foto/avatar: solo si se habilita/proporciona.
- Fines: administración de cuenta, funcionalidad, soporte y seguridad.

### Actividad de la app / contenido generado por el usuario
- Viajes, ofertas, estados y cancelaciones: Sí.
- Mensajes de soporte/servicio: Sí.
- Calificaciones/comentarios: Sí.
- Direcciones guardadas y contactos de confianza: Sí.
- Fines: funcionalidad, soporte y seguridad.

### Información financiera
- Historial/metadata de transacción y billetera: Sí cuando la función está activa.
- Express almacena importe, moneda, método, estado, comisión y referencias de transacción.
- No declarar que Express almacena número completo de tarjeta salvo que esto cambie en el producto.

### Información y rendimiento de la app
- Registros de fallos/diagnóstico: Sí.
- Fines: analítica técnica, seguridad y mejora de estabilidad.

### Identificadores
- Token de notificaciones / identificadores técnicos necesarios para push: Sí.
- Fines: funcionalidad y notificaciones.

## Data Safety — uso compartido

Supabase, Firebase Cloud Messaging y proveedores de infraestructura/mapas se usan como proveedores para operar Express. En Play, un proveedor que trata datos únicamente en nombre del desarrollador puede entrar en la excepción de "service provider"; confirmar contratos/configuración vigentes antes de marcar "No compartido".

No declarar venta de datos. Express no debe vender datos personales o sensibles.

## Seguridad de datos

- Datos transmitidos por HTTPS/TLS.
- RLS y autenticación en backend.
- La aplicación cliente usa publishable key; no service-role secret.
- Backups Android desactivados.
- Cleartext HTTP desactivado.
- Eliminación de cuenta disponible en la app y fuera de la app.

## Eliminación de cuenta

Ruta en app:
Perfil → Privacidad y datos → Eliminar mi cuenta.

Requiere confirmación explícita escribiendo `ELIMINAR`.

El backend elimina:
- Supabase Auth / credenciales.
- Perfil.
- Direcciones guardadas.
- Tokens/suscripciones push.
- Soporte y contactos de confianza.
- Calificaciones.
- Viajes/solicitudes propios.
- Billetera y registros personales asociados.
- Registros técnicos directamente asociados.

Se pueden conservar registros limitados y desidentificados únicamente cuando sean necesarios por seguridad, fraude, disputas, contabilidad u obligaciones legales, tal como explica la política de privacidad.

## Permisos Android esperados

Permitidos/esperados:
- INTERNET
- ACCESS_NETWORK_STATE
- ACCESS_COARSE_LOCATION
- ACCESS_FINE_LOCATION
- POST_NOTIFICATIONS
- VIBRATE
- WAKE_LOCK
- FOREGROUND_SERVICE
- FOREGROUND_SERVICE_LOCATION

No deben aparecer sin una revisión explícita:
- ACCESS_BACKGROUND_LOCATION
- MANAGE_EXTERNAL_STORAGE
- REQUEST_INSTALL_PACKAGES
- READ_SMS
- READ_CALL_LOG
- WRITE_CALL_LOG
- QUERY_ALL_PACKAGES

## Declaración de servicio en primer plano

Tipo: location.

Justificación propuesta para Play Console:
"Express usa un servicio en primer plano de ubicación únicamente cuando el conductor activa voluntariamente el estado En línea o durante un viaje activo. La ubicación permite mostrar al conductor en el mapa, actualizar su posición para el pasajero y prestar el servicio de transporte. Android muestra una notificación persistente mientras el seguimiento está activo. El seguimiento se detiene cuando el conductor sale del estado activo o la pantalla/flujo que lo requiere termina."

## Declaración de ubicación precisa

Justificación propuesta:
"Express es una aplicación de transporte. La ubicación precisa es necesaria para determinar un punto de recogida útil, encontrar conductores cercanos, mostrar la aproximación del conductor, navegar durante un viaje y proporcionar funciones de seguridad/SOS. Una ubicación aproximada puede situar al usuario a kilómetros del punto real y no es suficiente para una recogida segura."

## Funciones financieras

En el formulario de funciones financieras:
- La app no ofrece préstamos, crédito, inversión, criptomonedas ni apuestas.
- La app puede mostrar billetera/movimientos y métodos de pago asociados a servicios físicos de transporte.
- Verificar la categoría exacta que muestre Play Console en el momento de publicar.
- Los pagos por transporte son servicios físicos; mantener la descripción de la ficha coherente.

## Publicidad

Si Express no integra un SDK de anuncios en el AAB final, declarar **No contiene anuncios**.
Si se agrega publicidad posteriormente, actualizar Play Console, Data Safety y esta documentación antes de publicar.

## Público objetivo

Definir el público real del servicio. No seleccionar categorías infantiles solo para ampliar alcance. Si el servicio se destina a adultos/usuarios habilitados para contratar transporte, mantener la ficha, Términos y clasificación coherentes.

## Clasificación de contenido

Completar el cuestionario IARC con respuestas reales. Express contiene transporte, ubicación, mensajería de servicio y funciones SOS; no declarar contenido que no exista.

## Store listing

Necesario:
- Nombre de app.
- Descripción corta y completa.
- Icono 512×512.
- Feature graphic 1024×500.
- Capturas de teléfono.
- Email de soporte.
- Política de privacidad.
- Categoría adecuada (Maps & Navigation / Travel & Local según la ficha final).

## Release gate

Antes de producción:
- Flutter analyze/build sin errores.
- AAB firmado.
- targetSdk 36.
- package `com.express.usuario1`.
- Deep links de auth funcionales.
- Registro, confirmación de email y recuperación de contraseña probados.
- Eliminación de cuenta probada con una cuenta desechable.
- Política y página de eliminación accesibles públicamente.
- Cuenta(s) de revisión Play válidas.
- Data Safety sincronizado con esta documentación.
