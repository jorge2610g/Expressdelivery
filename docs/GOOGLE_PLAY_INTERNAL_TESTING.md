# Express → Google Play: Pruebas internas (configuración preparada, NO publicada)

## Estado y alcance

- Rama aislada: `work/google-play-internal-qa-20261018`. No se modifica `main` ni la producción de Express.
- Publicador: `.github/workflows/play-internal.yml` → `scripts/play_internal.py`.
- Paquete exacto: `com.express.usuario1`.
- ÚNICA pista permitida por el código: `qa` (Pruebas internas). Nunca `production`.
- Fuente de AAB: **GitHub Release oficial del workflow `Build Express Android`**, con tag inmutable SHA/job y `identity.json`. Nunca usar AAB de debug ni archivo local sin manifiesto.
- **Nuevo modo interno:** solicitud administrativamente autorizada con `artifact_type = aab` → compila y firma únicamente el AAB (omite `flutter build apk`). La release contiene exclusivamente `.aab` + `identity.json`.
- **Modo APK habitual:** mantiene `single-app-candidate-apk+aab` y continúa generando ambos archivos cuando corresponda.
- **Activación pendiente de revisión:** la Edge Function `android-build-worker` usada para firmar/registar builds requiere el código coordinado del PR, **no desplegado en Producción**. Hasta aprobarlo y desplegarlo, el modo AAB-only está preparado pero no operativo. No modificar el servicio activo sin revisión del flujo de producción.
- Firma: la misma del flujo actual que genera APK/AAB oficiales; el publicador no firma ni recompila.
- Por seguridad, se impide publicar sin una solicitud explícita y la frase `AUTORIZO PRUEBAS INTERNAS`.
- `check` abre una transacción descartable de Google Play, comprueba permisos, pistas y códigos de versión, **sin subir ni publicar**.

## Paso único que debe realizar el propietario

En GitHub → `jorge2610g/Expressdelivery` → **Settings → Secrets and variables → Actions → New repository secret**, crear:

- **Nombre:** `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
- **Valor:** el **contenido JSON completo** del archivo descargado de Google Cloud de la cuenta `play-publisher@blue-app-a077b.iam.gserviceaccount.com`, no la ruta ni solo el nombre del archivo.

NO subir el JSON al repositorio, issues ni al chat. No usar secrets como variables de repositorio. Si ya se filtró una clave, rotarla en Google Cloud. Conviene **retirar el permiso de Producción** de esa cuenta en Play Console, conservando solo la publicación en pistas de prueba.

La API de Android Publisher debe estar habilitada en `blue-app-a077b`; además la cuenta debe estar activa con acceso a `Express (com.express.usuario1)` en Play Console.

## Ejecutar verificación de conexión

Esta rama admite una solicitud controlada mediante la edición de **solo un archivo**:
`.github/play-internal/request.json`:

```json
{
  "mode": "check",
  "release_tag": "single-app-android-qa-v1.6.3-build141-sha1cd67f3956c5-job6edd1219",
  "confirmation": ""
}
```

Al crear/modificar ese archivo, GitHub Actions se inicia en la rama y valida el tag, SHA, AAB, credenciales y conexión. El tag arriba es un candidato ya existente que sirve para verificar el acceso API; **NO** es la versión corregida más reciente para publicar.

## Numeración automática verificada

- La verificación `check` lee los AAB/códigos ya usados en Google Play y calcula el **siguiente `versionCode` libre** sin hacer ninguna publicación: `max(máximo_en_Play + 1, código_del_candidato)`.
- Ejemplo confirmado por la API: máximo en Play `140`; candidato `1.6.3+141`; recomendación `141` (todavía disponible). Una vez consumido, se recomendará como mínimo `142`.
- Se puede mantener `versionName = 1.6.3`. **El número sugerido no se inyecta en un AAB ya firmado**: la próxima compilación oficial debe llevar ese código desde el origen y pasar el flujo de aprobación del SHA. Reescribir un AAB firmado rompería su trazabilidad.
- Las APK firmadas distribuidas fuera de Play pueden conservar `1.6.3+141` mientras se prueban y **no consumen** el `versionCode` en Google Play. Android podría impedir una instalación como actualización si hay otra APK del mismo paquete con `versionCode` mayor o una firma distinta.
- El flujo Play está en modo `check` por defecto. **Nunca sube automáticamente el Build 141** ni cualquier otro archivo; subir un AAB exige confirmación expresa y probadores preparados.

## Solicitar un AAB de Pruebas internas sin APK

**Precondiciones:** revisión y activación autorizada de la Edge Function coordinada, y cambios de workflow incorporados a la rama de firma `work/express-unified-android-build141`. No activar ni publicar automáticamente.

1. Un administrador autenticado crea en Express un trabajo Android aprobado para el SHA exacto que se quiere probar: `artifact_type=aab`, `version_name=1.6.3`, `build_number=141` si sigue libre. Se reutiliza la RPC protegida `admin_create_build_job`; no se salta la validación del administrador.
2. Con ese trabajo en estado `queued`, actualizar el archivo **existente** `.github/build-requests/android-141.json` con el UUID real, `source_sha` aprobado, versión y build. Solamente ese archivo dispara el workflow firmado con solicitud de propietario.
3. El flujo comprueba SHA/versión, descarga la misma clave oficial de Express mediante OIDC, compila **solo** `flutter build appbundle --release`, revisa la firma y recursos Android y publica GitHub Release con `.aab` e `identity.json`; no hay `.apk` ni checksum inventado.
4. El backend solo marca como `ready` cuando recibe el hash SHA-256 real del AAB y su URL; el campo APK permanece vacío. Si falla la firma, no se registra como correcto.
5. La publicación a Google Play está **separada**. Tras comprobar testers, código y permiso explícito de publicación, el workflow `play-internal.yml` puede enviar el AAB a la pista `qa`, **nunca a Producción**.

No cambiar el archivo de solicitud ni crear una versión de tienda hasta haber probado esta integración en QA.

## Subir una nueva versión (solo tras comprobar en QA)

1. Completar cambios Android/Realtime y, cuando la Edge Function y la rama de firma estén preparadas y autorizadas, generar un **AAB únicamente** con `artifact_type=aab` en el flujo oficial firmado. No compilar un APK adicional para esta pista.
2. Consultar el versionCode mayor de Play. Usar un `build_number` superior al mayor publicado/subido en cualquier pista. **No reutilizar Build 141 si Google Play ya lo recibió**.
3. Comprobar que la cuenta tiene permisos de pruebas, que existe la pista interna y que los testers están configurados en Play Console.
4. Modificar la solicitud, seleccionando el **tag real del nuevo candidato**, con:
   ```json
   {
     "mode": "publish",
     "release_tag": "TAG_OFICIAL_FIRMADO_DE_NUEVO_CANDIDATO",
     "confirmation": "AUTORIZO PRUEBAS INTERNAS"
   }
   ```
5. El flujo comprueba el SHA del tag y el SHA-256 del AAB, abre edit, inspecciona pistas, sube el AAB, modifica **solo `qa`**, valida y confirma el edit. Informa el resultado en GitHub Actions. Nunca publica en Producción.
6. Los testers deben aceptar la invitación/opt-in en Play y actualizar desde la tienda. El enlace de testers se gestiona en Play Console.

El flujo también admite `workflow_dispatch` si esta definición se incorpora posteriormente al default branch con revisión. Actualmente, al estar aislado del default branch, el disparador garantizado es el cambio firmado en `request.json`.

## Avisos

- Google Play App Signing puede instalar una app firmada con certificado distinto del usado para APK sideload del pipeline. Antes de desinstalar o reinstalar, verificar certificado y proteger datos en un dispositivo de pruebas.
- Si Play ya conoce el versionCode, una compilación posterior con ese mismo número no se puede subir para probarla: compilar un número nuevo.
- Tener Play Developer API conectada **no habilita automáticamente actualizaciones automáticas**. Una carga siempre requiere autorización expresa.
- La distribución interna de Google Play no aísla por sí misma el backend: usar cuentas/zonas Preview según las reglas de Express.
