# Ubicación en segundo plano para conductores

## Comportamiento

- Al abrir Express, pasajero y conductor reciben primero el permiso de ubicación “mientras se usa la app”. El arranque no pide ubicación en segundo plano.
- El conductor puede consultar el estado real en “Permisos y servicios”.
- Cuando toca “En línea”, Android se revisa localmente. Si el permiso no es “Permitir todo el tiempo”, Express explica por qué lo necesita y ofrece abrir los ajustes de la app. El conductor vuelve a Express y toca “En línea” otra vez.
- La app solo solicita al backend que active el estado en línea después de confirmar el permiso del sistema, obtener una ubicación actual y pasar las validaciones de elegibilidad que el servidor ya aplica.
- Pasajeros no necesitan ni se les pide el permiso de ubicación en segundo plano.

## Límite de plataforma

El permiso es una decisión del sistema operativo en ese dispositivo. El servidor no puede leer directamente los permisos Android; el teléfono debe comprobarlos con Geolocator. El backend sí valida que el perfil del conductor esté aprobado y que pueda activarse. No se guarda un booleano de permiso enviado por el cliente como si fuera una lectura confiable del sistema.

Android 11 y posteriores llevan al usuario a Ajustes para conceder ubicación en segundo plano. Express no puede habilitarla silenciosamente. Android y Google Play también requieren que el acceso en segundo plano sea necesario para la función principal y esté explicado claramente. La ubicación persistente del conductor mientras está En línea habilita la recepción y seguimiento de servicios; la revisión del formulario de Play Console debe describir esa experiencia con precisión.

## Preparación de Android

El scaffold Android se genera de nuevo en CI antes de aplicar el overlay. `.github/scripts/apply_floating_overlay.py` debe inyectar `ACCESS_BACKGROUND_LOCATION` de forma idempotente junto con sus permisos/servicios ya existentes. Así el permiso no depende de un directorio `android/` local que se puede regenerar.

## QA antes de Play Internal

1. Confirmar CI, análisis y contrato de manifiesto.
2. En ambos emuladores, borrar solo el permiso de ubicación desde Ajustes (no borrar datos de Express), abrir la app y confirmar que el inicio termina con el permiso “mientras se usa”.
3. En el conductor, tocar “En línea”; confirmar el aviso y que no se activa en el backend. Abrir ajustes, conceder “Permitir todo el tiempo”, regresar y tocar “En línea” de nuevo.
4. Confirmar que el estado solo cambia después de la comprobación del sistema y de las validaciones del servidor. Repetir en modo pasajero y confirmar que no solicita permiso en segundo plano.
5. Si Android/Play marca un incumplimiento de política o el comportamiento difiere en cualquiera de los dos emuladores, detener la carga a Play Internal y ajustar antes.

No crear viajes ni ofertas reales para esta verificación. La carga a Play Internal debe usar el artefacto oficial generado del mismo SHA que haya pasado esta QA y las autorizaciones del workflow.
