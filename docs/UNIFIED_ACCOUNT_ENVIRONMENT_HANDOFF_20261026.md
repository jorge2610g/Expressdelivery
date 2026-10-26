# Handoff: contextos por cuenta y release de Express

Fecha: 2026-10-26. Esta nota conserva el acuerdo operativo para que otro agente no revierta lo probado ni cree flujos paralelos.

## Decisión vigente

- Hay una sola carretera: mismo proyecto Supabase, mismas reglas de negocio y configuración canónica de ciudades, cobertura, zonas, tarifas y servicios para Prueba y Producción.
- El backend resuelve el contexto desde la cuenta autenticada. Las operaciones conservan ese contexto para impedir cruces entre pasajeros, conductores, comercios, viajes, envíos, pedidos, pagos, billeteras y trazabilidad.
- El pasajero de Prueba solo se asigna a conductores de Prueba; lo mismo aplica a Producción. El aislamiento debe estar en RPC/RLS/backend, no solo en la interfaz.
- Hay un solo Admin Express. Los filtros de entorno dentro de las secciones muestran operaciones autorizadas sin duplicar configuración ni cambiar permisos. Siguen vigentes los límites de rol, zona y módulo.
- Express Android/Web incluye cliente y conductor de Taxi, Envíos y pedidos de restaurante cuando los permisos y la configuración comercial de la zona lo permiten. Express Restaurante sigue siendo la app/portal del comercio. Admin sigue siendo un producto web separado.
- No crear Admin Preview, zonas de Preview duplicadas ni una segunda app de repartidor. No activar flags comerciales ni alterar pagos reales por el hecho de publicar código.

## Estado conocido después de la prueba del propietario

- El cambio de contexto por cuenta y filtros de operación se publicó en la web; el propietario informó que hizo las pruebas y “creo que sí quedó”. Esto confirma su prueba web, no certifica por sí solo cada zona, rol, pago ni integración de terceros.
- Android continúa el mismo flujo/código de Express. La candidata **1.6.4+148** ya fue compilada y cargada con éxito a Google Play Internal (workflow `40272024186`). No reutilizar su `versionCode`.
- La reparación de lectura de direcciones se prepara como **1.6.4+149**. El siguiente paso autorizado es compilar y subir el APK/AAB oficial solo al track **Internal** de Google Play para pruebas. No promover a Producción de Play Store. La publicación interna tampoco acredita QA de dispositivo: el propietario debe instalar y probar la versión.
- La subida automática debe provenir del workflow oficial y de una orden firmada por GitHub OIDC del propietario. No crear la candidata por SQL manual, no falsificar `auth.uid()`/claims ni saltarse funciones/RLS.

## Reglas de release Android

1. Un único paquete Android Express: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
2. La versión Flutter y el build deben concordar (`version: 1.6.4+148`) con el registro de release y el SHA exacto compilado.
3. Generar APK y AAB firmados como pareja inmutable del mismo job/SHA. Verificar hashes y fuente antes de publicar.
4. El destino permitido para esta solicitud es Google Play `internal`. El workflow de esta ruta no puede promover a `production`.
5. Registrar la candidata/resultado en `build_jobs`, el gate y el resumen de Actions. Informar por separado: compilado, artefactos, track, estado de QA. No afirmar éxito hasta comprobar esos registros.
6. Después de subir, el usuario prueba el build distribuido desde Internal. Para ir a producción de Play Store hace falta otra instrucción explícita.

## Invariantes para cambios futuros

- Antes de quitar una tabla/campo de entorno, comprobar y migrar las lecturas/escrituras de apps, Admin, Edge Functions, RPC, RLS y reportes. Preferir migraciones nuevas y reversibles; no editar migraciones ya aplicadas.
- No consolidar pagos, saldos, pedidos ni historiales de entornos distintos sin un plan de datos revisable. Configuración compartida no significa datos operativos mezclados.
- Cambios en la disponibilidad por ciudad son cambios de negocio separados del despliegue de software. Preservar los flags existentes salvo instrucción concreta.
- No tocar los worktrees/rutas locales que el propietario tenga sucios. Trabajar en rama nueva desde `main` actualizado.
- Revisar los archivos `AGENTS.md` de cada repositorio y esta nota antes de alterar el modelo. Si documentación histórica discrepa, prevalece esta directiva del 26-10-2026 solo para la decisión que describe; controles de seguridad, zonas y roles siguen vigentes.

## Verificación pendiente

Tras Internal: instalar build 149 y revisar con cuentas de Prueba que pasajero, conductor y pedidos compartan contexto; confirmar descripciones de origen/destino en selección, ofertas, seguimiento, notificaciones e historial; comprobar que ninguna cuenta de Producción vea ni reciba operaciones de Prueba; revisar Taxi, Envíos y Delivery si está habilitado en la zona. Mantener un registro de resultados reales, incluyendo módulo no habilitado, errores y configuración usada.
