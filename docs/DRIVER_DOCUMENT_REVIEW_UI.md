# Express · Corrección de revisión de documentos de conductor (2026-10-11)

## Alcance y reglas
- Aplicación: `Expressdelivery` (Flutter compartido entre Web y Android).
- Respaldar antes de tocar código: `backup/before-docs-profile-darkmode-20261011`.
- Rama: `fix/driver-docs-profile-darkmode-20261011`.
- Datos separados por `runtime_channel` desde Supabase; jamás usar QA para alterar conductores de Producción.
- Las partes aprobadas quedan bloqueadas; permitir reemplazo únicamente donde `review_parts[slot].status == rejected`. No rebajar seguridad ni saltar el backend.
- **Web primero**. No generar APK/AAB ni usar Google Play automáticamente.

## Causas verificadas en el código
1. `DriverSetupPage._captureManualIdentity` guardaba la captura solo en estado Flutter cuando la pantalla era una edición focalizada; el padre recargaba desde Supabase y volvía a pedir evidencia.
2. La vista `focusSection=profile` reutilizaba `_profileStep`, cuyo único botón abría el asistente completo de identidad; `_saveFocusedProfilePhoto` no aparecía en el pie de página.
3. `DriverKycCorrectionPage` mostraba un estado vacío si `driver_kyc_bolivia_review_state` no devolvía el identificador del documento. En ese caso se consulta el estado de onboarding del **propio usuario**. La autorización del reemplazo sigue siendo del servidor.
4. Varias tarjetas de documentos usaban colores de tema claro incluso con brillo oscuro.

## Comportamiento esperado
- Carné inexistente: asistente completo de frente, reverso y fotografía facial; en edición individual se persiste vía `update_my_driver_documents_for_review`; el trigger existente sincroniza la selfie de perfil.
- Carné existente: mostrar estados sin exigir capturar de nuevo tres fotografías. Frente, reverso y selfie aprobados/pending no se reenvían. Solo una evidencia explícitamente rechazada puede reintentarse mediante `driver_kyc_bolivia_replace_part`.
- Foto de perfil ausente: ofrecer selección de cámara o galería en una pantalla independiente, guardar mediante `update_my_driver_profile_photo_for_review`.
- Documentos adicionales: usar `colorScheme` de Flutter (surface, onSurface, primary, error), incluidos estados y avisos.

## QA pendiente antes de publicar
1. `flutter analyze` y `flutter test` desde el SHA de la PR; verificar ambos entrypoints `lib/web_preview.dart` y `lib/mobile_main.dart`.
2. Cuenta de conductor **Preview** con carné pending: entrar en Revisar; confirmar que no pide volver a subir nada y al regresar conserva el estado.
3. Carné con solo selfie rechazada y frente/reverso aprobados: permitir reemplazo de selfie y comprobar que los dos aprobados no cambian.
4. Foto de perfil sin imagen: subir nueva foto, guardar y recargar. Debe aparecer pendiente en vez de reabrir las tres capturas.
5. Cambiar a modo oscuro: comprobar tarjetas adicionales, chips, avisos y contraste.
6. Si el envío focalizado de identidad falla por requisito adicional obligatorio, **no** relajar validaciones del RPC en Producción: planificar un endpoint seguro para la corrección aislada.
7. Fusionar a `main` y confirmar despliegue GitHub Pages solo tras QA verde; la app Android requiere gate independiente.

## Límites
No se ha modificado la base Supabase ni se han promovido versiones o cambiado firma/Play Store. Este documento es especificación y registro de cambios en rama QA, **no** certificación de E2E ni publicación.
