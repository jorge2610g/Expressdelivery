# Ubicación del conductor mientras está en línea

## Comportamiento

- Al abrir Express, pasajero y conductor reciben primero el permiso de ubicación “mientras se usa la app”. El arranque no pide ubicación en segundo plano.
- El conductor puede consultar el estado real en “Permisos y servicios”.
- Cuando toca “En línea”, Android se revisa localmente. Se permite `whileInUse` o `always`; no se exige “Permitir todo el tiempo”.
- La app solo solicita al backend que active el estado en línea después de confirmar el permiso del sistema, obtener una ubicación actual y pasar las validaciones de elegibilidad que el servidor ya aplica.
- Durante el seguimiento, Geolocator inicia un servicio de ubicación en primer plano con notificación persistente. El conductor debe iniciar la sesión mientras Express está visible; Android puede mantener ese servicio al cambiar de app.
- Pasajeros no necesitan ni se les pide el permiso de ubicación en segundo plano.

## Límite de plataforma

El permiso es una decisión del sistema operativo en ese dispositivo. El servidor no puede leer directamente los permisos Android; el teléfono debe comprobarlos con Geolocator. El backend sí valida que el perfil del conductor esté aprobado y que pueda activarse. No se guarda un booleano de permiso enviado por el cliente como si fuera una lectura confiable del sistema.

Google Play revisa y aprueba por separado la declaración de `ACCESS_BACKGROUND_LOCATION`. Express no incluye ese permiso en la candidata 144: el flujo usa el servicio de ubicación en primer plano, iniciado desde la app visible, y una notificación persistente. El permiso del sistema no lo puede consultar el servidor; el cliente verifica el estado local y el servidor mantiene sus controles de aprobación/elegibilidad.

## Preparación de Android

El scaffold Android se genera de nuevo en CI antes de aplicar el overlay. `.github/scripts/apply_floating_overlay.py` no debe inyectar `ACCESS_BACKGROUND_LOCATION`; el gate de Google Play bloquea ese permiso restringido en esta candidata.

## QA antes de Play Internal

1. Confirmar CI, análisis y contrato de manifiesto.
2. En ambos emuladores, borrar solo el permiso de ubicación desde Ajustes (no borrar datos de Express), abrir la app y confirmar que el inicio termina con el permiso “mientras se usa”.
3. En el conductor con permiso “mientras se usa”, tocar “En línea” mientras Express está visible y confirmar el servicio de ubicación con notificación.
4. Cambiar a otra app sin cerrar Express y comprobar que el servicio conserva la ubicación. Confirmar que pasajero no inicia ese servicio de conductor.
5. Si Android/Play marca un incumplimiento de política o el comportamiento difiere en cualquiera de los dos emuladores, detener la carga a Play Internal y ajustar antes.

No crear viajes ni ofertas reales para esta verificación. La carga a Play Internal debe usar el artefacto oficial generado del mismo SHA que haya pasado esta QA y las autorizaciones del workflow.
