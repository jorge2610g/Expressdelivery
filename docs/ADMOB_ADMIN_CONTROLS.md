# AdMob — Módulo retirado por petición del propietario (2026-10-13)

**NO HABILITAR.** Las funciones de AdMob y la monetización con banners ya
no forman parte de Express. La librería `google_mobile_ads` y los widgets
fueron retirados; la compilación de Android ya no inyecta App ID ni Banner ID.
En el Supabase existente se pusieron todos los flags publicitarios de Pasajero
en `false` para los contextos de Prueba y Producción.

Los RPC y las columnas de esquema históricos se conservan por compatibilidad
con versiones anteriores; **no son una autorización para reactivar anuncios**.
No volver a agregar AdMob al panel, la web ni la APK sin una decisión explícita
del propietario.

Para cambios futuros usar `docs/GOOGLE_PLAY_SUBMISSION.md` y comprobar
manifiesto final, permiso `AD_ID`, SDKs y declaración de anuncios de Play
Console sobre la APK/AAB firmada. Publicar Web no produce ni valida una APK.
