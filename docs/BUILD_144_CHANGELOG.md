# Registro de cambios — Express Principal 1.6.3+144

Estado: **fuente preparada; build 144 aún no encolada ni compilada. No hay publicación en Google Play Producción.**

## Alcance del candidato

- App única oficial: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Versión fuente: `1.6.3+144`.
- El APK firmado descargable y el AAB de Google Play Internal deben generarse desde el mismo SHA con el workflow oficial y Flutter 3.47.5.
- La corrección de cancelación incluida: el pasajero ve la advertencia y el monto al cancelar después de que el conductor acepta; la espera y cuenta regresiva de cinco minutos corresponden solo al conductor después de “Ya llegué”.
- El monto y la moneda siguen gobernados por las reglas de zona. La corrección de cotización de backend ya está aplicada en Supabase Production; el texto Flutter requiere esta nueva build.

## Preparación de fuente

- Rama: `work/express-single-app-1.6.3-build142`; PR #270.
- Commit de versión y contrato: `5b0c24e2b922eab211df6b93a955e4d05f879b79`.
- `pubspec.yaml` y `test/android_release_approval_gate_test.dart` ahora esperan 144.
- El contenido anterior se conserva en el historial GitHub; no se alteró la rama estable.

## Gate de Google Play

Antes del ajuste, el baseline Production era 141, el siguiente código 143 y la candidata 143 estaba `ready` con SHA `e2ffce53293f3c339a0676fa75844c4e6ccd8b74`. Se reservó el código 144 mediante una actualización condicionada de una sola fila de `app_release_gate`. No se cambió el baseline, la candidata Production existente, la versión en Play, ni filas de usuarios, viajes o pagos.

Respaldo read-only inmediatamente anterior:

```json
{
  "platform": "android",
  "production_store_build_number": 141,
  "next_production_build_number": 143,
  "preview_build_id": "69e4e16c-ddc5-43ef-a640-c6253fccda3e",
  "preview_commit_sha": "db8b15b31eb59993508fe9b8d58430db8aa0738b",
  "preview_version_name": "1.6.1",
  "preview_build_number": 169,
  "production_candidate_build_id": "fbdab44b-f0cd-4c6a-8b96-67e6c4e9847c",
  "production_candidate_commit_sha": "db8b15b31eb59993508fe9b8d58430db8aa0738b",
  "production_candidate_version_name": "1.6.1",
  "production_candidate_build_number": 138,
  "production_candidate_promoted_at": null,
  "production_verified_build_job_id": "470dc53d-eeef-4acd-bbf9-b226344c043b"
}
```

Actualización condicionada: solo avanzó `next_production_build_number` a 144 cuando Producción seguía en 141, el contador estaba en 143 y el job 143 figuraba `ready`. La consulta de retorno confirmó baseline 141 y siguiente 144. Reversión posible antes de encolar 144: restaurar 143 únicamente si Producción continúa en 141, el contador sigue en 144 y no existe un job 144 en cola/compilación.

Esta modificación es un cambio de datos del gate, no una migración de esquema; no creó una entrada en el ledger. Quedó registrada aquí con su respaldo.

## Verificación CI de fuente

En el commit de bitácora `4030f4d66004ce97760b6167f606edd110344da7`, GitHub Actions:
- `Verify one-app Android release gate` pasó.
- `Express Release Change Inventory` pasó.
- `Express Single App - Web First QA` falló en la aserción de formato de marca (espera dos apariciones exactas de `Elige tu viaje`); el trabajo omitió análisis Flutter, suite de regresión y build Web después de esa falla. Debe revisarse antes de considerar validada la candidata.
- Otros flujos seguían en ejecución al registrar este estado.

## Pendiente para completar 144

- Encolar `1.6.3+144` desde Adminexpress con el RPC administrativo y el SHA fuente final de esta rama.
- Ejecutar el workflow oficial de APK+AAB, verificar firma, identidad y hashes, y cargar solo el AAB a Play Internal.
- Actualizar esta bitácora con UUID del job 144, SHA final, run, hashes, enlaces y resultado del preflight/carga.
- No promover ni publicar en Producción. QA y aprobación siguen siendo necesarias.
- La conexión SQL actual devuelve `auth.uid() = null` y `is_admin() = false`; no se insertó el job directamente ni se eludió el RPC. El navegador conectado no respondió durante la preparación, por lo que no pude encolar desde la sesión administrativa.

## Orden de QA antes de compilar y subir a Play

El flujo queda con un gate previo para que el versionCode no se consuma en Play antes de revisar la mejora:

1. Ejecutar CI y revisar que todos los checks requeridos de la fuente estén verdes.
2. Hacer checkout local del SHA candidato desde GitHub y correr `flutter run` en los dos AVD de Mac. La compilación temporal sirve solo para la prueba: no crea ni publica el APK firmado oficial ni sube una AAB a Play.
3. Validar ambos roles y el comportamiento de la mejora. Si algo falla, corregir en GitHub y repetir CI y emuladores sobre el SHA actualizado.
4. Solo tras aprobar QA se despacha el workflow oficial, confirmando `QA EMULADORES OK` y `AUTORIZO APK+AAB PRUEBAS INTERNAS`. La ejecución crea APK y AAB firmadas de la misma fuente/commit y sube la AAB únicamente a Pruebas internas.
5. La verificación en el teléfono desde Play es la revisión final. No hay promoción automática a Producción.

El gate técnico del workflow requiere ambas confirmaciones antes de entrar al job. La prueba manual debe corresponder al mismo SHA del trabajo encolado; si cambia código después de probar, se repiten las verificaciones. La compilación `flutter run` de QA puede crear una app de desarrollo necesaria para instalar en los emuladores, pero no es el artefacto oficial APK/AAB ni registra el versionCode en Google Play.

Estado de la build 144 al añadir este flujo: **todavía no compilada ni cargada**. La CI anterior sigue bloqueada por la aserción de marca de Web First QA; primero hay que repararla y volver a pasar los checks.

## Verificación del gate emulador-first en GitHub

- El workflow `.github/workflows/build-android.yml` ahora exige dos inputs antes de entrar a la compilación oficial: `QA EMULADORES OK` y la autorización explícita de carga interna. La prueba de contrato comprueba que ambos gates existan.
- En el commit `e1d6a0a448592f42735a715b1ad6b41ff9ed8879`, `Verify one-app Android release gate` y `Express Release Change Inventory` pasaron.
- `Express Single App - Web First QA`, run `39870427314`, falló en la aserción `screen.count("'Elige tu viaje'") == 2`. El archivo de pantalla de la rama no contiene ese título ni `¿A dónde vas?`; falta verificar visualmente el flujo actual del pasajero antes de decidir si corresponde corregir la app o actualizar el contrato de QA.
- El gate no se considera completo mientras ese fallo siga. No se generó APK/AAB oficial, no se subió la 144 a Play y no se probó funcionalmente la mejora en los AVD.
