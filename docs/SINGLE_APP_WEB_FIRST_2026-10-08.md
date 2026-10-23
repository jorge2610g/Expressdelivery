# Arquitectura oficial de Express

**Decisión confirmada por el propietario el 14 de octubre de 2026.**

## Estado vigente — 2026-10-23

La regla definitiva vigente está en `AGENTS.md`: existe una sola APK/AAB Android oficial y una sola Web oficial. Cualquier texto histórico de este documento que describa una Web o APK de Preview separada queda revocado.

- Web oficial: `https://expressviajes.online/` (`lib/web_main.dart`).
- Registro independiente de conductor: `/registro/conductor` y `/?registro=conductor`, dentro del mismo dominio y bundle. No crear subdominio ni permitir viajes desde este formulario.
- El inicio Web normal permanece en modo pasajero. La publicación Web automática desde `main` solo actualiza el bundle del dominio oficial; no puede cambiar roles, autorización backend, flags comerciales ni el contrato de una sola app.
- PR #270 se integró en `main` y se desplegó la Web oficial. El ajuste posterior del portal y del arranque está en PR #274; la QA del API 37 aún no termina, así que no se ha vuelto a desplegar esa corrección.
- Flujo de Android 1.6.3+144: CI → build temporal del SHA candidato → QA en dos emuladores → build firmado oficial APK/AAB desde el mismo SHA → carga de AAB solo a Pruebas internas. Producción requiere autorización separada.
- No activar el correo de aprobación: migración y configuración siguen aplazadas por el propietario.

Express Principal utiliza una sola aplicación Android, identificador `com.express.usuario1`, con el único punto de arranque `lib/mobile_main.dart`. La aplicación se distribuye como un APK/AAB oficial firmado. No se crean paquetes ni APK independientes para pruebas.

La web de clientes es única: https://expressviajes.online/. El panel administrativo es también único: https://admin.expressviajes.online/. Las cuentas de Preview y de Producción acceden a la misma implementación web, no a URL ni despliegues alternativos.

`preview` y `production` son contextos internos de autorización y datos, resueltos por el servidor tras autenticar a cada cuenta. Las políticas RLS/RPC y los filtros de zona, rol, usuarios, conductores, viajes, pagos, billetera y pedidos deben impedir cruces de datos.

## Trabajo y publicación
1. Escribir una sola implementación compartida.
2. Ejecutar pruebas unitarias, de integración y de aislamiento de cuentas.
3. Publicar solo en el dominio canónico solicitado, sin construir una segunda web.
4. Validar con una cuenta de prueba en el mismo sitio.
5. Generar un candidato Android únicamente cuando el propietario lo solicite, con el paquete y firma oficiales.
6. Aprobar de forma separada cualquier publicación a Google Play.

El flujo Android oficial es `single-app-candidate-apk+aab`: un mismo APK/AAB para QA físico y posterior promoción sin recompilar. No se permite volver a introducir aplicaciones, configuraciones, workflows o artefactos separados exclusivamente por el entorno de pruebas.

El aislamiento interno Preview/Producción debe permanecer activo. Esto no autoriza cambios en módulos comerciales o datos reales de Producción.
