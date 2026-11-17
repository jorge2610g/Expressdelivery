# Preparación iOS para App Store — 17-11-2026

Estado: **código preparado, sin compilar en macOS, sin subir nada**.
Decisión del propietario: lanzar la primera versión iOS con planes de conductor pagados por QR dentro de la app, y ver qué responde Apple en la revisión.

## Qué está en el repositorio

| Pieza | Archivo | Estado |
|---|---|---|
| Inicio con Apple (solo iOS, junto a Google) | `lib/auth_entry.dart`, `lib/auth_apple_nonce.dart` | Compila y pasa análisis. Pruebas del nonce OK. Flujo real sin probar. |
| Overlay iOS (Info.plist, entitlements, pbxproj, Podfile) | `.github/scripts/apply_ios_overlay.py`, `ios_overlay/Runner/Runner.entitlements` | Probado contra un proyecto iOS generado por `flutter create`: idempotente, Podfile con sintaxis Ruby válida, entitlements solo en el target Runner. |
| Workflow manual de build iOS | `.github/workflows/build-ios.yml` | Solo `workflow_dispatch`. YAML válido. **No ejecutado.** |
| Pruebas de contrato | `test/ios_app_store_prep_contract_test.dart`, `test/auth_apple_nonce_test.dart` | 13 pruebas pasan. |
| Dependencias nuevas | `pubspec.yaml`: `sign_in_with_apple` ^8.2.0, `crypto` ^3.0.8 | Resueltas. |

Permisos declarados en `Info.plist`: cámara, micrófono, ubicación en uso, ubicación «siempre» (ver riesgos), fotos y cifrado exento. Modos en segundo plano: solo notificaciones remotas. **No hay ubicación en segundo plano en iOS.**

## Qué no se puede comprobar desde este entorno

- Compilar, firmar o archivar: hace falta macOS con Xcode. El workflow lo hace en `macos-latest`.
- Que `xcodebuild` acepte el `project.pbxproj` modificado.
- Que el login con Apple funcione de punta a punta (requiere el proveedor Apple configurado en Supabase y un dispositivo iOS).
- Que las notificaciones lleguen a iPhone (requiere APNs y la app de iOS registrada en Firebase).

## Pendiente de tu lado

Apple Developer (cuenta personal, activa):
1. Registrar el App ID `com.express.usuario1` con las capacidades **Sign in with Apple** y **Push Notifications**.
2. Crear una clave de App Store Connect (API key) con rol de App Manager. Guardar en GitHub, como secretos del repositorio:
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_PRIVATE_KEY` (contenido completo del `.p8`)
   - `APPLE_TEAM_ID`
3. Crear la app en App Store Connect con bundle `com.express.usuario1`.

Supabase:
4. Activar el proveedor **Apple** en Authentication, con el bundle `com.express.usuario1` como Client ID nativo, y añadir `com.express.usuario1://login-callback/` a las URL de redirección permitidas.

Firebase:
5. Registrar una app iOS con bundle `com.express.usuario1` y subir la clave APNs (`.p8`) en Cloud Messaging.
6. Guardar en GitHub los valores de esa app iOS como secretos: `IOS_FIREBASE_API_KEY`, `IOS_FIREBASE_APP_ID`, `IOS_FIREBASE_MESSAGING_SENDER_ID`, `IOS_FIREBASE_PROJECT_ID`, `IOS_FIREBASE_STORAGE_BUCKET`.
7. Las notificaciones push a iOS necesitan además que la función `express-push-dispatch` acepte `client_config=ios`. Hoy solo acepta `android`. **Cambiar y desplegar esa función requiere tu autorización**, porque afecta a producción.

App Store Connect (cuando haya un build):
8. Capturas (6.9" y 6.5"), descripción, URL de privacidad y de soporte, clasificación de edad, etiquetas de privacidad.
9. Notas para revisión con una cuenta de prueba que funcione. Hay que explicar el cobro de planes: el plan es el pago por intermediar viajes físicos (ver riesgos).

## Riesgos conocidos para la revisión

- **Planes de conductor por QR (guía 3.1.1).** Apple podría exigir In-App Purchase porque el plan da acceso a funciones de la app. Se envía así por decisión del propietario; si lo rechazan, hay que implementar IAP para esos planes.
- **Ubicación «siempre».** La app pide ubicación en segundo plano en Android para conductores. En iOS el código no la usa, pero el permiso «siempre» se declara. Conviene quitar esa petición en iOS o justificarla; si Apple la ve sin uso real, puede rechazar la app.
- **Conductores en iPhone sin ubicación en segundo plano.** El rastreo solo corre con la app abierta. Esto afecta a la asignación de viajes en iOS y no está resuelto.
- **Llamadas ZEGO en segundo plano.** Puede requerir modos de fondo adicionales (audio/VoIP) y CallKit. No se han añadido; hay que verificarlo en macOS con llamadas reales.
- **Número de build.** TestFlight exige un número de build nuevo por subida. Hoy se toma de `pubspec.yaml` (`+169`), que también usa Android. Hay que subirlo antes de cada subida a TestFlight.
- **Cuenta personal.** La app aparecerá en la tienda con el nombre legal de la cuenta personal.

## Cómo lanzar el build (cuando lo ordenes)

1. Configura los secretos de las secciones 2 y 6.
2. Lanza **Build Express iOS** manualmente en GitHub Actions sin marcar `upload_testflight`: compila, firma y deja el IPA como artefacto.
3. Revisa el IPA. Solo si das la orden, vuelve a lanzarlo con `upload_testflight` marcado para subirlo a TestFlight.

Nada de esto se publica ni se sube sin tu orden explícita.
