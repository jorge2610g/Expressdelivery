# AGENTS.md — Expressdelivery

## DIRECTIVA VIGENTE DEL PROPIETARIO (24-10-2026)
- Android Express Principal conserva `com.express.usuario1` y `lib/mobile_main.dart`.
- Los conductores de Taxi, Envíos y pedidos de restaurantes usan esa misma app, las mismas pantallas y el mismo flujo. Para pedidos comerciales cambia únicamente la etiqueta visible del servicio; se conservan permisos y validaciones backend.
- Express Restaurante sí es una app Android separada para la operación del comercio, construida en `jorge2610g/Express_Restaurante` y basada en el portal existente `/restaurantes/`. No incluye cliente, Taxi ni administración global.
- No crear una app separada `Express_Repartidor` ni duplicar pantallas de conductor.
- Admin Express sigue en su repositorio y producto existentes.

La instrucción de 24-10-2026 actualiza las propuestas de arquitectura del 14-10-2026. Los registros históricos se conservan como historia, no como especificación vigente.

## Contextos y despliegue
- Android único: `com.express.usuario1`, Flutter entrypoint `lib/mobile_main.dart`.
- Web única de clientes: https://expressviajes.online/ desde `lib/web_main.dart`.
- Panel administrativo único: https://admin.expressviajes.online/ en el repositorio `jorge2610g/Adminexpress`.
- Preview y Producción son contextos internos por cuenta, no otros binarios o URLs. La app de restaurante es un producto operativo separado y no un binario para Preview.
- **Preview y Producción son contextos internos de CUENTA**, no otros binarios ni URLs. La identidad autenticada determina el contexto mediante el backend y se conserva estrictamente el aislamiento de zonas, tarifas, usuarios, conductores, viajes, pedidos, liquidaciones, documentos, cuentas, permisos, notificaciones y pagos con reglas de RLS/RPC.
- Nunca permitir que pruebas cambien datos reales ni que modificaciones a la web de ambos contextos activen módulos comerciales por zona automáticamente.

## Ciclo obligatorio
1. Implementar cambios una sola vez en el código y Web compartidos.
2. Correr análisis, tests, verificación de aislación de Preview/Producción interna y QA.
3. Cuando se solicite desplegar para prueba, publicar solo en el dominio oficial. Probar con una cuenta de pruebas en ese mismo sitio.
4. Solo producir Android si el propietario solicita expresamente **la APK única oficial**, firmada y con el mismo identificador `com.express.usuario1`. Verificar permisos, hashes, versión y Google Play release gate. Promoción a Play Store requiere aprobación separada; no deducirla de una prueba.
5. Mantener separadas las funciones del comercio en Express Restaurante, sin duplicar los flujos de conductor Express.
6. Ninguna modificación puede interrumpir Taxi/Envíos ni desactivar servicios en Producción sin autorización expresa.

## Arquitectura de productos
Express Principal conserva los flujos de cliente y conductor, incluidos los pedidos comerciales aceptados por conductores autorizados. Express Restaurante atiende pedidos, catálogo y liquidaciones del comercio. No suprimir tablas de comercios, backend de delivery ni liquidaciones hasta comprobar migración completa y QA E2E.

## Compilación y seguridad
- `.github/workflows/build-android.yml` admite únicamente el paquete oficial y artefactos candidatos oficiales.
- `.github/workflows/deploy-web.yml` compila únicamente `lib/web_main.dart` para el dominio real.
- `.github/scripts/check_single_app_contract.py` debe impedir que se reintroduzcan paquetes y pipelines paralelos.
- En Android, las llamadas privadas de ZEGO requieren `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS` y solicitud de permiso de micrófono antes de llamar. Si se deniega, no enviar la invitación.
- No guardar secretos/keystore en Git. No recrear credenciales antiguas de un segundo paquete.
- Conservar siempre las migraciones históricas ya aplicadas: no volver a ejecutarlas, editarlas o borrarlas para eliminar huellas de un APK. Crear nuevas migraciones para cambios de esquema.

## Documentación vigente
- `README.md`
- `docs/EXPRESS_DELIVERY_PRODUCT_DECISIONS_20261024.md`
- `docs/MIGRATION_PROVENANCE_20261024.md`
- `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`
- `docs/EXPRESS_CODE_AUDIT_AND_FOUR_APP_PLAN_20261014.md`
- `docs/PRIVATE_VOICE_CALLS.md`

Cualquier instrucción histórica acerca de una aplicación o web de Preview separada queda revocada y no tiene autoridad para agentes, asistentes ni compiladores.
