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

## QA del servicio foreground (build 1.6.3+144 en Play Internal)

1. Confirmar CI, análisis y contrato de manifiesto.
2. En ambos emuladores, borrar solo el permiso de ubicación desde Ajustes (no borrar datos de Express), abrir la app y confirmar que el inicio termina con el permiso “mientras se usa”.
3. En el conductor con permiso “mientras se usa”, tocar “En línea” con Express visible y confirmar que inicia el servicio foreground con notificación persistente. No exigir el permiso “Permitir todo el tiempo”.
4. Cambiar a otra app sin cerrar Express y comprobar que Android mantiene el servicio y la actualización de ubicación. Confirmar que el pasajero no inicia ese servicio de conductor.
5. La build 1.6.3+144 está subida a Play Internal. En un AVD limpio, la APK oficial firmada llegó a la pantalla de acceso; la prueba autenticada de “En línea” y de la notificación foreground sigue pendiente. Los AVD con sesiones existentes tienen firma debug distinta; se actualizaron con una build debug del mismo SHA sin borrar datos. No desinstalarlos para reemplazar la firma.

No crear viajes ni ofertas reales para esta verificación. La APK de esta build ya está publicada en Play Internal. Se confirmó el arranque en limpio, pero no se marcó completa la QA de dispositivo porque falta una sesión autenticada de conductor para probar “En línea” y la notificación persistente.
