# Express Principal

Aplicación única de Express para Taxi, Envíos y Delivery, con una Web oficial de clientes. Este resumen refleja el estado revisado el **23 de octubre de 2026**; las notas históricas de documentos anteriores no sustituyen estas reglas.

## Contrato oficial

- Android: paquete `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Web de clientes y registro aislado de conductores: `https://expressviajes.online/`, entrypoint `lib/web_main.dart`.
- Panel administrativo: `https://admin.expressviajes.online/`, repositorio `jorge2610g/Adminexpress`.
- Registro de conductor: `https://expressviajes.online/registro/conductor` o `https://expressviajes.online/?registro=conductor`. Es una ruta de la Web oficial, no otro sitio ni otra aplicación.
- La Web normal es solo para pasajeros. La ruta directa de registro reutiliza la cuenta y el formulario documental existente; tras aprobación muestra la descarga de la app oficial. El envío de correo de aprobación está aplazado.
- Preview y Producción son contextos internos de cuenta/backend. No crear otra APK, dominio, subdominio o pipeline para Preview.

## Estado de trabajo vigente

- PR #270 está integrado en `main` (`3c7bf0c7901d647f10d86213d4b78245d2d15391`) y la Web oficial se desplegó correctamente.
- La migración de bloqueo de solicitudes Taxi por deuda está aplicada en Supabase Production como `20261023071944`. No ejecutar de nuevo migraciones históricas.
- PR #274 (`fix/144-startup-and-driver-registration-ui`) contiene estabilización de arranque, el asset de marca reparado, dependencia FCM, corrección del estado aprobado del portal y el ajuste de permisos ZEGO. Está sincronizado con `main`, es integrable y todos sus checks requeridos de GitHub pasan.
- Build candidata `1.6.3+144`: QA visual en 5554/API 37 y 5556/API 34 muestra los flujos de conductor y pasajero, mapas cargados, tarifa y Waze/PIN en la pantalla del pasajero. La APK debug temporal tiene el mismo certificado y conservó las sesiones. ZEGO registra permisos vacíos al sincronizar sesión; no aparece el prompt de micrófono al iniciar. El primer frame tardó 14–30 segundos en algunas aperturas de la APK debug de QA; el tiempo de una release firmada aún no está medido.
- La suite completa pasó **409/409** localmente; los análisis Flutter, la suite de regresión y la compilación Web también pasaron en GitHub para el código actual.
- Chrome muestra en `/registro/conductor` la pantalla de bienvenida del portal de conductor, no la pantalla de pasajero. Tras integrar el PR hay que recargar y validar también `/` para confirmar el modo pasajero en la Web oficial actualizada.
- No se ha generado ni subido el APK/AAB oficial a Google Play Pruebas internas. Falta integrar el PR, comprobar el despliegue final de la Web y ejecutar el workflow oficial desde el mismo código validado. No promover a Producción.
- No aplicar la migración de correo ni configurar el proveedor de email: quedaron expresamente aplazados.

## Reglas para contribuir y publicar

1. Implementar una sola vez en el código compartido y documentar alcance, pruebas y estado real.
2. Correr checks y verificar aislamiento de cuenta/contexto. Para probar la app, usar solo sesiones y datos QA; no crear viajes o deudas reales.
3. Para la Web, desplegar solo al dominio oficial tras integrar en `main`, y comprobar pasajero y ruta directa de registro en Chrome.
4. Generar APK/AAB solo desde el workflow oficial y desde el SHA que pasó emuladores. Mantener firma e identidad oficial; subir la AAB solo a Pruebas internas cuando el gate esté verde y solicitado. Producción requiere aprobación separada.
5. No guardar secretos ni keystore en el repositorio. Preservar migraciones ya aplicadas y crear nuevas para cambios de esquema.

## Continuidad y especificaciones

- [Estado y bitácora de Build 144](docs/BUILD_144_CHANGELOG.md)
- [Web única y flujo Web First](docs/SINGLE_APP_WEB_FIRST_2026-10-08.md)
- [Auditoría y arquitectura vigente](docs/EXPRESS_CODE_AUDIT_AND_FOUR_APP_PLAN_20261014.md)
- [Política de documentación](docs/DOCUMENTATION_POLICY.md)
- [Permiso de ubicación en segundo plano](docs/DRIVER_BACKGROUND_LOCATION.md)
- [Llamadas privadas](docs/PRIVATE_VOICE_CALLS.md)

Los documentos fechados en octubre 14 y anteriores contienen decisiones y planes históricos. Cuando contradigan el contrato oficial, este README y el `AGENTS.md` vigente tienen prioridad; no reactivar propuestas de aplicaciones o webs separadas.
