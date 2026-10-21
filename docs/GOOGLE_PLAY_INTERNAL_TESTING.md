# Express 1.6.3+142 — Google Play Pruebas internas

## Alcance y guardas

- Solo acepta un Release oficial de GitHub con APK + AAB juntos, `identity.json`, paquete `com.express.usuario1`, versión `1.6.3`, build `142`, hashes coincidentes y tag ligado al SHA del artefacto.
- La carga solo selecciona una pista existente `qa` o `internal`. El publicador no permite seleccionar `production`.
- `check` valida credenciales, pista y disponibilidad del `versionCode`, sin subir el AAB.
- `publish` requiere la confirmación exacta `AUTORIZO PRUEBAS INTERNAS`; un build ya usado por Play se rechaza.
- Al actualizar la pista, el publicador conserva las releases y `versionCodes` internos ya existentes antes de añadir el 142.
- El APK y AAB descargados deben coincidir con los dos hashes del mismo `identity.json`. El publicador sube a Play solo el AAB; la APK queda en GitHub Release para QA.

## Requisitos externos

1. Debe existir en GitHub Actions el secreto `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` con la clave de la cuenta Play Publisher esperada. El valor secreto nunca se incluye en el repositorio ni en logs.
2. Esa cuenta debe tener acceso a `Express (com.express.usuario1)` y permiso para pistas internas. Debe existir una pista `qa` o `internal` y estar configurado el grupo de testers.
3. La candidata 142 oficial debe haber finalizado antes como un único job APK+AAB y tener un Release firmado con sus tres assets. No se acepta el job/AAB de 141 ni archivos locales.
4. El candidato oficial nuevo debe crearse mediante el RPC administrativo existente. La creación directa de filas o la omisión de `public.is_admin()` no está permitida.

## Ejecución

El workflow `.github/workflows/play-internal.yml` escucha cambios en `.github/play-internal/request.json` en la rama 142 y también define `workflow_dispatch` cuando esté disponible desde GitHub Actions. El archivo de solicitud no debe añadirse hasta que exista el Release 142.

Verificación sin publicar:

```json
{
  "mode": "check",
  "release_tag": "single-app-android-qa-v1.6.3-build142-sha<12-hex>-job<8-hex>",
  "confirmation": ""
}
```

Tras confirmar en los logs que la pista y el código están disponibles, publicación interna:

```json
{
  "mode": "publish",
  "release_tag": "single-app-android-qa-v1.6.3-build142-sha<12-hex>-job<8-hex>",
  "confirmation": "AUTORIZO PRUEBAS INTERNAS"
}
```

No usar la frase de confirmación hasta haber aprobado el SHA, los hashes y el destino. Si Play ya conoce el código 142, no reutilizar este AAB: se necesita una nueva versión de build aprobada y firmada.

## Pruebas locales

```sh
python3 -m py_compile scripts/play_internal.py
python3 scripts/play_internal.py --self-test
```

Estas pruebas comprueban identidad, hashes y selección de pista; no realizan llamadas a Google Play ni sustituyen la verificación real de credenciales y testers.
