# Bolivia · Didit hasta 30 sesiones / mes y recepción manual

Estado: cambios aislados en PR #124 (apoya el PR #123). NO desplegados en Supabase ni Android.

## Alcance
- Solo BO. Chile mantiene el flujo anterior.
- Cuota: hasta 30 sesiones iniciadas con Didit por mes calendario en zona horaria America/La_Paz, separando producción y QA.
- Se incluyen sesiones Didit existentes del mes al inicializar. Cuenta sesiones, NO factura/decisiones aprobadas. Hay que contrastar contra la cuenta de Didit: los créditos podrían compartirse con verificaciones chilenas y el reset financiero podría ser otro día.
- Reserva atómica transaccional desde Edge Function ANTES de llamar a Didit; usuarios no pueden reservar por API pública. La llamada directa al endpoint tampoco evita el límite.
- Después del cupo se activa manual: anverso, reverso y selfie, con imágenes en bucket privado `driver-onboarding`. Los usuarios nunca reciben un estado «verificado» por el solo hecho de enviar imágenes.
- El backend exige las capturas de identidad manuales cuando no se utiliza Didit verificado. Los demás documentos obligatorios continúan.
- La opción administrativa `automatic`, `didit` o `manual` puede alternarse por canal. La preferencia Didit NO permite saltar el límite de 30.
- Las revisiones manuales autorizadas cambian únicamente el estado de identidad/documento. La aprobación del conductor requiere la acción administrativa ya existente.
- Usuarios con documentos manuales pendientes, aprobados o rechazados mantienen ese método al cambiar de mes para poder completar correcciones.
- La experiencia de captura inicial usa la cámara nativa mediante image_picker con pasos e instrucciones personalizados; NO presenta todavía una vista de cámara interna con rectángulos detectados en tiempo real. No realiza prueba de vida automática.
- Extracción OCR de documento manual: pendiente; el número de carné se solicita al conductor para revisión.

## Implementación
- Migraciones 20261008190500 (PR #123), 20261008202500 y 20261008204000.
- Edge Functions didit-identity-prod y didit-identity.
- Flutter driver_setup.dart + driver_manual_identity_capture.dart.
- Panel Adminexpress, PR #37.
- No hay credenciales nuevas ni permisos públicos a tablas de quota; únicamente funciones controladas por Supabase RLS y roles.

## Condiciones de publicación obligatorias
1. Verificar coincidencia de ciclo de 30 con la cuota de crédito de Didit y otros workflows.
2. Aplicar migraciones en orden y desplegar Edge y Android de forma coordinada; una app vieja no sabrá cambiar al modo manual.
3. Probar QA de Preview: cuotas 28,29,30,31 con 3 usuarios simultáneos, solicitudes repetidas, retrasos del proveedor, fallos de conexión, reinicio de mes y alternancia manual.
4. Comprobar permisos del admin, aislamiento de Preview y Producción, URLs privadas firmadas y lectura de evidencias desde panel.
5. Probar un registro completo de conductor BO manual y otro Didit con datos reales de prueba autorizados.
6. Establecer e implementar eliminación automática de evidencias biométricas/manuales temporales y aviso/consentimiento específico, antes de liberar Producción.
7. Pasar compiles, tests y QA del release firmado, sin modificar identificador o firma Android.
