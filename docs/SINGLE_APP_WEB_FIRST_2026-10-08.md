# Arquitectura oficial de Express

**Decisión confirmada por el propietario el 14 de octubre de 2026.**

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
