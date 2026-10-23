# Express Principal

Aplicación única de Express para Taxi, Envíos y Delivery, con una Web oficial de clientes. Este resumen refleja el estado revisado el **23 de octubre de 2026**; las notas históricas de documentos anteriores no sustituyen estas reglas.

## Contrato oficial

- Android: paquete `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Web de clientes y registro aislado de conductores: `https://expressviajes.online/`, entrypoint `lib/web_main.dart`.
- Panel administrativo: `https://admin.expressviajes.online/`, repositorio `jorge2610g/Adminexpress`.
- Registro de conductor: `https://expressviajes.online/registro/conductor` o `https://expressviajes.online/?registro=conductor`. Es una ruta de la Web oficial, no otro sitio ni otra aplicación.
- La Web normal es solo para pasajeros. La ruta directa de registro reutiliza la cuenta y el formulario documental existente; tras aprobación muestra la descarga de la app oficial. El envío de correo de aprobación está aplazado.
- Preview y Producción son contextos internos de cuenta/backend. No crear otra APK, dominio, subdominio o pipeline para Preview.

## Estado de trabajo vigente — 2026-10-23

- **Cambios integrados:** PR #274 (`aa3be317d979a820e66dbe270637b42805f27688`) y PR #275 (`6daa510fd3762bb150b8cfa6785b4ce63076b705`) están en `main`. Mantienen la única app Android `com.express.usuario1` y el dominio oficial de clientes/registro.
- **Web oficial:** el despliegue del commit `6daa510` terminó correctamente (Actions run [39949802486](https://github.com/jorge2610g/Expressdelivery/actions/runs/39949802486)); Web First QA pasó (run [39949802489](https://github.com/jorge2610g/Expressdelivery/actions/runs/39949802489)). Chrome abrió `https://expressviajes.online/registro/conductor` y mostró la pantalla final del portal: documentos aprobados, botón “Descargar app” y guía para usar las mismas credenciales. Es evidencia de que la ruta directa carga el flujo de registro, pero el estado mostrado pertenece a la sesión QA ya abierta; no se creó usuario ni se envió formulario. `/?registro=conductor` está soportada por código y CI; la raíz `/` sigue siendo la experiencia de pasajero. El correo de aprobación continúa aplazado.
- **Corrección pendiente de publicar:** se reprodujo que una cuenta existente podía volver al inicio de pasajeros al autenticarse desde el enlace de registro. La rama `fix/driver-registration-auth-route` conserva la intención de registro durante el retorno de autenticación OAuth y restaura la ruta; el test de regresión pasó 5/5 y la compilación local de Web terminó. Falta integrar y confirmar el despliegue oficial; la verificación final con una cuenta QA autenticada queda pendiente, sin usar cuentas ni datos reales.
- **Build 144 en Pruebas internas:** el workflow oficial [39950965142](https://github.com/jorge2610g/Expressdelivery/actions/runs/39950965142) terminó en éxito, compiló APK+AAB firmados de `com.express.usuario1`, versión `1.6.3+144`, y subió la AAB a Google Play **Internal**. Release de GitHub: [build 144](https://github.com/jorge2610g/Expressdelivery/releases/tag/single-app-android-qa-v1.6.3-build144-sha6daa510fd376-jobf3ad62a9). SHA-256 APK: `a1a292bf99abd576a9923d455bba8ee65b22a142285642e928e536dc34102868`; AAB: `fc165e5ff7db6ef7695ba046e72cfd31a3255b408a72b4d8b2f8f7f328c2aaae`. El proveedor de Play aceptó la carga; la disponibilidad para testers puede depender del procesamiento de Google Play.
- **Pruebas:** suite Flutter completa 409/409, análisis y Web First QA pasaron para el código integrado; en esta sesión se repitieron **38/38 pruebas focalizadas** con Flutter 3.47.2 (contrato de arranque, permisos, bloqueo por deuda, mensaje único al conductor, confirmación de tarifa, cache/ruta de mapa y rutas del portal). El workflow oficial Android construyó con la versión fijada y pasó política Play, identidad y firma. En el AVD limpio `ExpressQA144`, la APK oficial firmada 1.6.3+144 hizo un arranque frío y mostró el acceso en español en 8.764 s (`am start -W`). Fine/coarse location estaban denegados y no apareció el diálogo GPS antes de iniciar sesión, acorde con que el gate pide ubicación después de autenticar; probar ese paso requiere una sesión QA. En `emulator-5556`, el APK temporal de QA del mismo SHA actualizó la instalación existente sin desinstalar ni borrar datos; la vista de pasajero mostró una sola tarjeta, tarifa `Bs 5.50`, estado y acción Waze. Waze abrió Chrome como fallback porque no había manejador de `waze://`. En `emulator-5554`, la captura mostró el aviso de Android “System UI isn't responding” sobre Express; `dumpsys activity lastanr` informó que no hubo ANR desde el arranque y los logs consultados no muestran `FATAL EXCEPTION` de Express, por lo que no se atribuye el aviso a un ANR de la app. No se confirmó perfil conductor ni se recorrió la deuda con una cuenta QA aislada. La prueba autenticada de conductor/deuda sigue pendiente; no hubo cancelaciones, aceptación de ofertas, pagos ni escrituras de datos reales.
- **Cambios de producto cubiertos:** bloqueo de nuevas solicitudes Taxi por deuda, mensaje accionable en billetera sin nombrar proveedor, deduplicación del aviso del conductor, tarifa visible al pasajero, navegación externa por Waze, descarte de la línea recta provisional del mapa, rutas/registro web de conductor y mejoras del arranque GPS. La guía de ubicación describe el servicio foreground y la notificación persistente. No se agregó proveedor de mapas de pago.
- La migración de bloqueo de deuda ya se aplicó en Supabase Production como `20261023071944`; no volver a ejecutarla. Email de aprobación y su migración siguen aplazados. No se promovió el AAB a Producción ni se desplegó un lanzamiento Production en Play.

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
