# Avisos Android Play Store - Express (2026-10-12)

- El APK de Producción consulta `latest_app_release('android')` cada 15 minutos y compara `PackageInfo.buildNumber`; el gate funciona para pasajeros y conductores.
- Registrar una release requiere un build Android `apk+aab` firmado de Producción, vinculado a un candidato *QA certificado, aprobado y promovido*.
- **No registrar ni enviar avisos hasta verificar que la misma compilación está realmente disponible en Google Play.** El registro requiere aceptación explícita del administrador; no despliega a Google Play.
- `admin_register_play_store_release` conserva el control previo `admin_publish_build` y guarda la URL oficial `com.express.usuario1`. Por defecto es opcional; solo convertir en obligatoria cuando el despliegue de Play tenga cobertura suficiente.
- `admin_send_release_update_notice` prepara el texto desde la última release publicada y solo envía al confirmar desde el panel. Admite `all`, `drivers` y `passengers`, y opcionalmente una zona.
- El aviso usa la campaña `admin_send_announcement_v4`; la separación Preview/Producción sigue por `audit_test_group_members`.
- El número de destinatarios no prueba entrega FCM. Validar push e inbox en Android físico después de registrar una release real.
- **Migración aditiva**: crear únicamente las dos funciones administrativas; no modifica `app_releases`, no publica versiones ni envía notificaciones por sí sola.
