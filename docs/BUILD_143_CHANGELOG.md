# Registro de cambios — Express Principal 1.6.3+143

Estado: **release 1.6.3+143 compilado y cargado a Google Play Internal; Producción sigue en 141 y no se promovió**.

## Motivo
El propietario solicitó pasar a `versionCode=143` porque indicó que Google Play ya no aceptará el 142. Verifiqué que el workflow del candidato 142 completó exitosamente la validación de versión y el paso **Upload the paired AAB to Google Play Internal** (run 39651704456). El panel del backend conservaba la base de Producción 141 y el siguiente código 142, por lo que repetirlo habría colisionado con el candidato ya cargado a Internal.

## Fuente y cambios
- Continúa la única aplicación oficial: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Versión en `pubspec.yaml`: `1.6.3+143`.
- Actualizada la prueba de contrato para exigir que el código fuente y la candidata declaren `1.6.3+143`.
- Se conserva la funcionalidad de cobros zonales de cancelación del PR #270.
- Se agregó una migración guardada que reserva el siguiente código 143 sin cambiar el baseline de Producción 141.
- El PR #117 de Adminexpress elimina el tope visual de 142 y muestra el siguiente build que entrega el gate.
- No se promovió nada a Producción.

## Respaldo previo al cambio del release gate
Snapshot de solo lectura tomado antes de aplicar la migración, en UTC 2026-10-22:

```json
{
  "platform": "android",
  "production_store_build_number": 141,
  "next_production_build_number": 142,
  "production_verified_build_job_id": "470dc53d-eeef-4acd-bbf9-b226344c043b",
  "production_candidate_build_id": "fbdab44b-f0cd-4c6a-8b96-67e6c4e9847c",
  "production_candidate_commit_sha": "db8b15b31eb59993508fe9b8d58430db8aa0738b",
  "production_candidate_version_name": "1.6.1",
  "production_candidate_build_number": 138,
  "production_candidate_ready_at": "2026-10-08 07:51:19.615+00",
  "production_candidate_promoted_at": null,
  "updated_at": "2026-10-19 15:01:13.343452+00"
}
```

Candidato interno 142 verificado: job `9968a88f-df3e-4530-b805-cd1242ef2f07`, SHA `d1512d172d02f463f3db61caa111cfd6ab104dba`, estado `ready`, artefacto `single-app-candidate-apk+aab`. El workflow 39651704456 terminó `success`, incluida la subida a Internal.

La migración conserva `production_store_build_number=141`, permite reservar `next_production_build_number=143` cuando el candidato Android 1.6.3/142 está listo, y actualiza trigger, guardas y RPC del ciclo de candidatos para respetar esa reserva. En una reversión controlada, restaurar 142 únicamente si la Producción aún figura en 141 y el siguiente código sigue en 143:

```sql
UPDATE public.app_release_gate
   SET next_production_build_number = 142,
       updated_at = now()
 WHERE platform = 'android'
   AND production_store_build_number = 141
   AND next_production_build_number = 143;
```

## Resultado del release 143 — 2026-10-22

- PR #270 permanece abierto en borrador. SHA compilado: `e2ffce53293f3c339a0676fa75844c4e6ccd8b74`; rama `work/express-single-app-1.6.3-build142`.
- Las ocho comprobaciones del HEAD del PR terminaron correctamente, incluido release gate, inventario y QA Web First.
- Adminexpress PR #117 se fusionó en `a9493529784e3fb5d671d8efb1d5827d4ab164a9`; workflow deploy `39857338183` terminó success en el dominio oficial.
- La migración de reserva versionada se ejecutó en el SQL Editor autenticado de Supabase. Consulta posterior confirmó `production_store_build_number=141`, `next_production_build_number=143`. Esta ejecución directa no creó una entrada en el ledger de migraciones; reconciliar el historial con el flujo del repositorio antes de futuras migraciones, sin volver a ejecutar esta migración.
- Edge Function `android-build-worker` desplegado como versión 44, `verify_jwt=false` (el handler valida GitHub OIDC y restringe repo, rama, workflow, actor y candidato).
- Candidata encolada desde Adminexpress: job `bffa0a7f-b052-4f38-81c1-85de2896c662`, `single-app-candidate-apk+aab`, estado `ready`.
- GitHub Actions Build Express Android #812 / run `39859205262` terminó success. Flutter 3.47.5; paquete `com.express.usuario1`; `1.6.3+143`; APK y AAB del mismo commit y firma oficial. El verificador de identidad confirmó APK `com.express.usuario1 v1.6.3 build 143`.
- APK SHA-256: `da6ab2381a1062fb2d44e2d57874adaa4046a0085853bd68e45cce2fff1187bf`.
- AAB SHA-256: `e7ec79a9bd3c5f8b6aa9e9f65188a56ca7f734e9c334eb7cf643f933ab881f84`.
- ZIP de artefactos GitHub, id `12460864185`, SHA-256 `4c26fdd056b4106362a5c7e15b674e465b333b50b4dff943de41e0a2aa3184e2`.
- [Descargar APK firmado para QA](https://github.com/jorge2610g/Expressdelivery/releases/download/single-app-android-qa-v1.6.3-build143-shae2ffce53293f-jobbffa0a7f/express-single-app-candidate-v1.6.3-build143.apk) · [Descargar AAB firmado](https://github.com/jorge2610g/Expressdelivery/releases/download/single-app-android-qa-v1.6.3-build143-shae2ffce53293f-jobbffa0a7f/express-single-app-candidate-v1.6.3-build143.aab).
- Google Play preflight aceptó `com.express.usuario1`, pista `internal`, código 143; la carga terminó con “Carga completada en Google Play Internal: 1.6.3+143; sin cambios en Producción”.
- No se promovió ni publicó en Producción. La candidata aún requiere QA Android y aprobación explícita en el panel antes de cualquier promoción.

## Alcance de rollback

Se conservó el snapshot del gate previo en esta bitácora. No ejecutar un rollback del contador ahora que existe el job listo 143 y un AAB 143 en Internal: eso podría permitir colisiones. El baseline de Producción continúa en 141.


## Hallazgo del release gate — 2026-10-22

La primera reserva guarded de 143 no se aplicó. La inspección del trigger `trg_normalize_android_production_counter` mostró que la función `normalize_android_production_counter()` reescribía cualquier valor como `production_store_build_number + 1`. Además, las RPC de cola, certificación y promoción y el Edge Function del worker también asumían que el candidato debía ser exactamente Producción + 1. Con la base real de Producción en 141 y el 142 ya cargado a Internal, esa regla hacía imposible encolar 143.

La migración versionada ahora conserva el baseline real 141, permite reservar un versionCode posterior al baseline para el candidato unificado, y mantiene las validaciones de build, firma, SHA, certificación y aprobación. El worker acepta únicamente el candidato 1.6.3+143 desde el workflow/branch de release autorizado. La misma APK+AAB 143 podrá pasar por el flujo existente de QA y aprobación; esta reserva no marca Producción como 143 ni promueve la app.

La migración versionada y el Edge Function ya están aplicados/desplegados, según el resultado del release que sigue. No ejecutar manualmente solo el `UPDATE` anterior: el trigger restauraría 142.