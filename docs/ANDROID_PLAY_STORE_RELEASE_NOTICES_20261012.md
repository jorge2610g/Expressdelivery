# Avisos Android Play Store - Express (2026-10-12)

**Implementación sin migraciones nuevas en Supabase.**

- El APK de Producción consulta `latest_app_release('android')` cada 15 minutos y compara `PackageInfo.buildNumber` para pasajeros y conductores.
- Adminexpress registra versiones con **la función existente** `admin_publish_build`, solo cuando el administrador confirma que la misma compilación ya está disponible en Play Store. El panel exige QA certificado, aprobación y promoción del candidato.
- El aviso nativo muestra siempre el enlace oficial de la aplicación `com.express.usuario1`. Si una fila histórica no dispone de `play_store_url`, usa el enlace fijo de Google Play (no instala APK manualmente).
- El panel permite anunciar una versión registrada con la **función existente** `admin_send_announcement_v4`, escogiendo conductores/pasajeros/todos y ámbito global/una zona. El backend conserva el aislamiento por `audit_test_group_members`.
- El aviso masivo **nunca** se envía automáticamente al publicar la versión. Cada campaña exige confirmación de administrador.
- La nueva protección de Play Store solo llega a teléfonos cuando se instale una nueva compilación Android. No confundir desplegar Flutter Web con publicar el AAB en Play Console.
- No crear ni modificar filas de `app_releases` hasta contar con un AAB realmente publicado; no enviar campañas de Producción durante QA.
- Las métricas de destinatarios no prueban recepción de FCM. Validar el botón e inbox en APK real.
