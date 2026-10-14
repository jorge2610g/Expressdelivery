# Licencia del conductor: revisión individual y auditoría del aviso de actualizaciones

**Estado actualizado 2026-10-11:** el propietario autorizó aplicar la migración de licencia al Supabase compartido. Se ejecutó correctamente mediante Supabase y quedó registrada como versión `20261012021954`, nombre `driver_license_individual_evidence_review`. La función `admin_driver_license_review_part` y el trigger `trg_driver_license_part_states` existen; `anon` no tiene ejecución. La licencia existente de Producción mantiene estado `verified`. **No hay licencias de Preview registradas para QA E2E; la UI aún no está fusionada ni desplegada.** Conservar las ramas PR en borrador y exigir validación Preview antes de publicar la interfaz. La migración compartida es aditiva, no equivale a aprobación del flujo ni a publicación web.


**Fecha:** 2026-10-11 · **Estado:** migración aplicada a Supabase compartido por autorización explícita; interfaz aún en QA.

## Nueva revisión de licencia (backend aplicado, QA funcional pendiente)
- Tabla actual: `driver_documents` con `front_object_path`, `back_object_path`, `review_parts jsonb`, `status` y `requirement_id`.
- A diferencia del carné, el trigger histórico solo creaba estados `review_parts` para identidad; la licencia quedaba con un solo estado documental.
- Nueva migración propuesta `20261012021954_driver_license_individual_evidence_review.sql`: trigger antes de insert/update y RPC `admin_driver_license_review_part` restringido a administradores y entorno del conductor. Frente/reverso tienen estados, motivo y versión separados; el documento solo queda verified si ambas caras están aprobadas. Rechazar/reemplazar una imagen no modifica la aprobación de la otra.
- El RPC registra auditoría y una notificación de cambio de estado. El cliente administrativo se modifica en el repositorio separado `Adminexpress`; no hay implementación alterna para Preview.
- **Excepción autorizada:** la migración ya está instalada en el Supabase compartido porque el propietario lo autorizó expresamente. Solo instala función/trigger y no reescribe licencias existentes. No publicar la interfaz ni hacer revisiones de licencias reales antes de QA con cuenta Preview; la rama de prueba replica la misma implementación y no puede escribir datos Producción.

## Auditoría: actualizaciones de Express, conductor y pasajero
- `lib/mobile_main.dart` monta `AndroidReleaseUpdateGate` para la app Android de Producción, sin distinción conductor/pasajero; el paquete Preview monta `ExpressPreviewOverlay` y no obliga actualizarse mediante el gate de Producción.
- `lib/mobile_update_gate.dart` consulta `latest_app_release('android')` al inicio y después cada **15 minutos**, lee `PackageInfo.buildNumber`; ofrece APK/Play Store y bloquea solo si `mandatory=true`.
- RPC `latest_app_release` ya existe: busca `app_releases` `platform='android'` y `status='published'`, mayor número de build. **Resultado de auditoría (2026-10-11): 0 registros Android published.** En consecuencia el usuario no verá un aviso hasta publicar/configurar una release autorizada; no crear una publicación ficticia.
- `lib/web_main.dart` integra `AppUpdateBanner`, que consulta `version.json` cada **10 minutos** y ofrece actualizar la web sin recarga automática. El workflow `deploy-web.yml` genera marcador de versión.
- Seguridad: no omitir gate firmado/certificado, no mostrar builds de Preview como publicados en la Play Store de Producción, conservar canal y SHA de release.

## QA requerido
- CI Flutter + release gate.
- Cuenta Preview y Producción verificadas: al cambiar una sola cara de licencia permanece intacto estado de la otra; un documento sin foto no puede aprobarse.
- Subida por conductor de solo la parte rechazada y actualización del estado en una recarga.
- Disparador de notificaciones Push sobre `notifications` debe probarse en APK real; insertar una notificación en SQL **no** prueba entrega FCM/web push.
- Release futura: publicar solo build certificado y verificar el banner/aviso en móvil real.
