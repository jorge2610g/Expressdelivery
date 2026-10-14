# AGENTS.md — Expressdelivery

## REGLA DEFINITIVA DEL PROPIETARIO (14-10-2026)
**Una APK oficial y una web oficial de Express.**
- Android único: `com.express.usuario1`, Flutter entrypoint `lib/mobile_main.dart`.
- Web única de clientes: https://expressviajes.online/ desde `lib/web_main.dart`.
- Panel administrativo único: https://admin.expressviajes.online/ en el repositorio `jorge2610g/Adminexpress`.
- No crear, reintroducir ni compilar aplicaciones Android, paquetes Firebase, APK/AAB, webs, subdominios, publicadores, ramas de despliegue o bundles diferentes para Preview.
- **Preview y Producción son contextos internos de CUENTA**, no otros binarios ni URLs. La identidad autenticada determina el contexto mediante el backend y se conserva estrictamente el aislamiento de zonas, tarifas, usuarios, conductores, viajes, pedidos, liquidaciones, documentos, cuentas, permisos, notificaciones y pagos con reglas de RLS/RPC.
- Nunca permitir que pruebas cambien datos reales ni que modificaciones a la web de ambos contextos activen módulos comerciales por zona automáticamente.

## Ciclo obligatorio
1. Implementar cambios una sola vez en el código y Web compartidos.
2. Correr análisis, tests, verificación de aislación de Preview/Producción interna y QA.
3. Cuando se solicite desplegar para prueba, publicar solo en el dominio oficial. Probar con una cuenta de pruebas en ese mismo sitio.
4. Solo producir Android si el propietario solicita expresamente **la APK única oficial**, firmada y con el mismo identificador `com.express.usuario1`. Verificar permisos, hashes, versión y Google Play release gate. Promoción a Play Store requiere aprobación separada; no deducirla de una prueba.
5. Nunca introducir una segunda aplicación para corregir un problema de la aplicación real.
6. Ninguna modificación puede interrumpir Taxi/Envíos ni desactivar servicios en Producción sin autorización expresa.

## Arquitectura de productos
Express Principal conserva cinco recorridos: cliente Taxi, cliente Envíos, cliente Delivery/restaurantes, conductor Taxi y conductor Envíos. `Express_Repartidor` y `Express_Restaurante` son aplicaciones **funcionalmente distintas**, no alternativas QA de Express Principal. `Adminexpress` es un único panel. No suprimir tablas de comercios, backend de delivery ni liquidaciones hasta comprobar migración completa y QA E2E.

## Compilación y seguridad
- `.github/workflows/build-android.yml` admite únicamente el paquete oficial y artefactos candidatos oficiales.
- `.github/workflows/deploy-web.yml` compila únicamente `lib/web_main.dart` para el dominio real.
- `.github/scripts/check_single_app_contract.py` debe impedir que se reintroduzcan paquetes y pipelines paralelos.
- En Android, las llamadas privadas de ZEGO requieren `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS` y solicitud de permiso de micrófono antes de llamar. Si se deniega, no enviar la invitación.
- No guardar secretos/keystore en Git. No recrear credenciales antiguas de un segundo paquete.
- Conservar siempre las migraciones históricas ya aplicadas: no volver a ejecutarlas, editarlas o borrarlas para eliminar huellas de un APK. Crear nuevas migraciones para cambios de esquema.

## Documentación vigente
- `README.md`
- `docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`
- `docs/EXPRESS_CODE_AUDIT_AND_FOUR_APP_PLAN_20261014.md`
- `docs/PRIVATE_VOICE_CALLS.md`

Cualquier instrucción histórica acerca de una aplicación o web de Preview separada queda revocada y no tiene autoridad para agentes, asistentes ni compiladores.
