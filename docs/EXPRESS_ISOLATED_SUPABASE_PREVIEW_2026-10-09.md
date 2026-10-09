# Express Delivery — aislamiento físico Preview / Producción (2026-10-09)

## Objetivo

**El mismo commit y el mismo entrypoint Flutter**, con dos APKs de distintos
paquetes y dos proyectos Supabase independientes. Los usuarios, viajes,
identidades, documentos, tokens push, credenciales y configuraciones de prueba
NO se comparten con Producción.

| Elemento | Producción | Preview |
| --- | --- | --- |
| Supabase | `zgpijrznvaskgcmauwxx` | `xbphilqezmwfjfpdbwad` |
| Android package | `com.express.usuario1` | `com.express.usuario.preview` |
| Build flag | `EXPRESS_PREVIEW_MODE=false` | `EXPRESS_PREVIEW_MODE=true` |
| Credenciales | Publicable Production; secretos Production | Publicable Preview; secretos de prueba |
| FCM/push | Sistema actual de Producción | **DESHABILITADO** hasta integrar proyecto Firebase Preview independiente |
| Cobros/receptores externos | Proveedores reales | Deshabilitados, o credenciales sandbox distintas |

## Protección implementada en código

- `lib/core/supabase_client.dart` selecciona el proyecto **antes** de
  restaurar una sesión. En un APK Preview faltan los `--dart-define`
  de Preview, se muestra error de arranque y NO se conecta a Producción.
- Valida URL HTTPS y referencia Supabase exacta según el APK compilado, clave
  publicable separada y coincidencia con el canal compilado.
- `lib/core/express_supabase_bootstrap.dart` ejecuta la validación antes
  de `Supabase.initialize`; las sesiones se guardan con el ref de proyecto
  correspondiente. No se acepta cambio de proyecto por rol o sesión.
- `lib/push_notifications_native.dart` no obtiene Firebase config, no
  inicializa FCM ni registra tokens en APK Preview mientras
  `EXPRESS_PREVIEW_PUSH_ENABLED=false`.
- Incluso con push habilitado en el futuro, el binario exige el ID de Firebase
  de Producción para comprobar que el Firebase Preview es distinto.
- El workflow Android compila ambos APK desde el **mismo source SHA** con
  `EXPRESS_PREVIEW_MODE` y los valores correctos para cada base.
- Los jobs y claves de compilación Android siguen en el sistema existente de
  Producción, **no** se envían al Supabase Preview. Esto es infraestructura
  de distribución, no tráfico de usuarios de prueba.

## Estado de funciones del servidor — NO declarar listo antes del QA

- Supabase Preview tiene esquema, RLS, funciones SQL, buckets sin documentos
  reales y configuración de prueba; **no** contiene usuarios ni vehículos de
  Producción.
- Las Edge Functions de Producción no han sido publicadas automáticamente en
  Preview. No copiar webhooks, pago ni `express-push-dispatch` hasta disponer
  de secretos de sandbox y URLs de callback aisladas.
- El trigger de despacho push de Producción contiene una URL literal al
  Supabase real. **Está intencionalmente ausente en Preview**. Copiarlo ahí
  sin reconfigurarlo enviaría solicitudes desde Preview hacia Producción.
  Nunca activar ese trigger mientras apunte al proyecto Production.
- Un conjunto de funciones heredadas de OTP/DIDIT siguen disponibles como
  mecanismos antiguos apagados; no reactivar proveedores externos sin aprobación.
- La aprobación de tres fotos/documentación y el estado final de conductor,
  junto con la revisión de vehículo/licencia desde Admin Express, requieren QA
  de punta a punta en un usuario de prueba antes de promoción.

## Condiciones para activar push en Preview

1. Crear Firebase **Preview**, distinto del proyecto Firebase de Producción,
   con app Android `com.express.usuario.preview`.
2. Configurar en el pipeline los datos públicos Firebase Preview y el ID de
   Firebase Producción usado para comprobar la desigualdad.
3. Implementar `express-push-dispatch` en Supabase Preview apuntando
   **exclusivamente** a su Firebase Preview, con token/credencial de prueba.
4. Cambiar `EXPRESS_PREVIEW_PUSH_ENABLED` solo tras validar con los IDs de
   ambos Firebase y comprobar que Preview NO puede enviar a tokens reales.
5. Probar que los tokens de Preview solo se insertan en Supabase Preview, que
   el envío prueba llega únicamente a los teléfonos inscritos en Preview y
   que los webhooks/callbacks nunca alcanzan Producción.

## Promoción sin copiar datos de clientes

Los cambios en funciones, triggers, tablas y RLS se versionan como
migraciones revisables. No exportar `auth.users`, `public.users`,
`driver_profiles`, `driver_documents`, `storage.objects`,
viajes, notificaciones ni credenciales reales. Publicar solo migraciones
validadas y código del mismo commit. No eliminar ni reconstruir tablas
existentes de Producción.

**Estado de esta rama:** medidas preventivas de compilación y base de Preview,
sin publicación Android ni cambio de Producción; falta conexión Edge,
revisión end-to-end y aprobación expresa para promover.
