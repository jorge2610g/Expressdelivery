# Registro de cambios — Express Principal 1.6.3+143

Estado: **fuente 1.6.3+143 preparada en el PR #270; la reserva requiere aplicar el gate corregido antes de encolar**.

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

La migración solo cambia `next_production_build_number` de 142 a 143 cuando el baseline continúa en 141 y el candidato Android 1.6.3/142 está listo. En una reversión controlada, restaurar 142 únicamente si la Producción aún figura en 141 y el siguiente código sigue en 143:

```sql
UPDATE public.app_release_gate
   SET next_production_build_number = 142,
       updated_at = now()
 WHERE platform = 'android'
   AND production_store_build_number = 141
   AND next_production_build_number = 143;
```

## Pendiente para generar artefactos
1. Aprobar validaciones del SHA final del PR #270 y del PR #117 de Adminexpress.
2. Aplicar la migración versionada de reserva del build 143.
3. Desplegar el cambio del administrador para mostrar/enqueuear el número dinámico.
4. Encolar el job oficial `single-app-candidate-apk+aab` ligado al SHA final.
5. Ejecutar el workflow Android oficial con Flutter 3.47.5, `lib/mobile_main.dart`, paquete oficial y overlay nativo; APK y AAB deben compartir commit, versión e identidad.
6. Confirmar hashes y que el AAB quede en Internal. Esto no publica en Producción.


## Hallazgo del release gate — 2026-10-22

La primera reserva guarded de 143 no se aplicó. La inspección del trigger `trg_normalize_android_production_counter` mostró que la función `normalize_android_production_counter()` reescribía cualquier valor como `production_store_build_number + 1`. Además, las RPC de cola, certificación y promoción y el Edge Function del worker también asumían que el candidato debía ser exactamente Producción + 1. Con la base real de Producción en 141 y el 142 ya cargado a Internal, esa regla hacía imposible encolar 143.

La migración versionada ahora conserva el baseline real 141, permite reservar un versionCode posterior al baseline para el candidato unificado, y mantiene las validaciones de build, firma, SHA, certificación y aprobación. El worker acepta únicamente el candidato 1.6.3+143 desde el workflow/branch de release autorizado. La misma APK+AAB 143 podrá pasar por el flujo existente de QA y aprobación; esta reserva no marca Producción como 143 ni promueve la app.

La migración todavía debe aplicarse y el Edge Function `android-build-worker` desplegarse antes de crear el job. No ejecutar manualmente solo el `UPDATE` anterior: el trigger restauraría 142.