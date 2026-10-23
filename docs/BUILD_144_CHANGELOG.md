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

## Avance posterior de QA — 2026-10-22

Este bloque reemplaza los estados anteriores de CI fallido: la restauración de las dos pantallas completas quedó en el SHA probado y Web First QA volvió a pasar.

- SHA actual de la rama: `423174fcd0d019c8fb4b096ecfb599aa376a2b2f`.
- GitHub Actions para ese SHA: release gate, inventario, rutas de cuenta, llamadas privadas, onboarding, identidad global y Web First QA terminaron en **success**. Web First ejecutó análisis de `lib/`, suite Flutter y compilación Web.
- Flutter local confirmado: **3.47.5**. Los tests focalizados `test/floating_overlay_ci_contract_test.dart` y `test/android_release_approval_gate_test.dart` pasaron (10 tests).
- El primer build Android detectó un defecto de preparación: el script del overlay no añadía Firebase Messaging cuando el scaffold generado no tenía un bloque `dependencies`. Se corrigió `.github/scripts/apply_floating_overlay.py` para crear el bloque en ese caso, se agregó una prueba de contrato y la compilación temporal pasó.
- `flutter run -t lib/mobile_main.dart` generó el APK debug temporal e instaló `com.express.usuario1`, `1.6.3+144` (versionCode 144), en los dos AVD. La compilación fue del SHA anterior a este bloque, sin firma oficial; no crea release ni consume el código en Play.
- Hot Reload y Hot Restart se ejecutaron en el AVD Medium Phone. Sin embargo, el sistema UI de ambos emuladores mostró “System UI isn't responding” y no pude validar visualmente login, los roles ni el diálogo de cancelación. El AVD Medium Phone arrancó Android 17 beta y el Pixel 34 avisó que Google Play Services está desactualizado.
- Por ese problema de los emuladores, **QA funcional no está aprobado**. No se encoló el job 144, no se generó APK/AAB firmada, no se cargó nada a Play y no se creó ningún viaje/deuda de prueba en backend.

### Estado y paso para desbloquear QA

El flujo emulator-first está implementado en GitHub: CI verde → `flutter run` temporal → revisión en dos emuladores → solo después, compilar APK+AAB oficiales del SHA validado y cargar únicamente la AAB a Internal con ambas confirmaciones. Hay que reiniciar/estabilizar Android System UI en ambos AVD y observar la app antes de marcar `QA EMULADORES OK`. Mantener producción intacta.



## Estado de QA actualizado — 2026-10-22

- SHA de la rama verificado: `4825d63ad9dbcfb67ae5d0c531355aeb5b20999c`.
- Los ocho workflows asociados a ese commit finalizaron en **success**, incluido Web First QA, inventario de cambios y gate de release Android.
- Flutter 3.47.5: las pruebas focalizadas de confirmación de cancelación, contrato FCM/overlay y gate Android pasaron (**12 tests**).
- En ambos AVD arranca la app oficial `com.express.usuario1`, versión `1.6.3`, versionCode `144`: Android 17 beta/API 37 (emulator-5554) y Android 14/API 34 (emulator-5556). Las dos pantallas de acceso de Express se renderizan correctamente.
- La prueba visual de login y del flujo de cancelación aún no se completó: ambos AVD están en el inicio de sesión tras la instalación temporal limpia. Hace falta iniciar las cuentas de QA y recorrer el flujo de pasajero y conductor para marcar QA funcional como aprobada.
- No se encoló ni compiló la release oficial firmada; no se subió AAB a Play Internal ni se publicó en Producción.


## 2026-10-23 — Comisión por zona y servicio

| Fecha | SHA/Referencia | Archivo(s) | Operación | Antes → después / motivo | Impacto | Pruebas y evidencia | Estado |
|---|---|---|---|---|---|---|---|
| 2026-10-23 | PR #270 commits `9c69c0f` (texto de billetera), `d661539` (migración) | `supabase/migrations/20261023101500_zone_service_commission_settlement.sql`, `lib/express_account_pages.dart` | Añadido/modificado | Antes: el settlement solo leía `app_settings.commission_percent`, ignorando el porcentaje editable en la tarifa efectiva de zona/servicio; la billetera mostraba ese global como comisión de todos los viajes. Ahora: calcula la comisión de Taxi/paquetería/delivery con la regla efectiva por servicio y zona; Preview consulta su almacén aislado y solo usa la comisión global como respaldo si no existe regla. La billetera aclara que depende de zona y servicio. | Cálculo futuro de movimientos/comisiones. No modifica tasas, transacciones existentes, suscripciones ni reglas de acceso del conductor. | Migración aplicada a Supabase Production como `zone_service_commission_settlement_20261023101500`. Lectura posterior confirmó que la función activa usa `effective_fare_rule`, conserva el canal Preview aislado y el trigger `payment_wallet_settlement_trigger` sigue siendo AFTER INSERT. Tarifas activas observadas: global, Iquique/economy, Trinidad/economy y Trinidad/motorcycle en 0%; no se creó ningún pago ni movimiento de prueba. Revisión estática del SQL y `git diff --check`: PASS; no se ejecutaron tests automatizados ni QA de transacción. | Backend aplicado; cambios de interfaz quedan en este PR y requieren la siguiente compilación para verse en Android. Sin eliminaciones. Respaldo previo de la función en `/private/tmp/express-commission-backup/settle_wallet_payment.before.sql` (SHA-256 `f1e0fbead7e3433dab0e63ee52579e6ed7b83798687040997484176b97260772`). |


## 2026-10-23 — Registro de conductores desde la web oficial

| Fecha | Archivos | Operación | Impacto | Estado |
|---|---|---|---|---|
| 2026-10-23 | `lib/web_main.dart`, `lib/auth_entry.dart`, `lib/driver_registration_web_portal.dart`, `supabase/migrations/20261023120000_driver_web_registration_approval_email.sql`, `supabase/functions/driver-approval-email/index.ts` | Añadido | El dominio oficial ofrece acceso al registro de conductores. El acceso admite correo/contraseña y OAuth de Google; el callback conserva la ruta de registro. La ficha, requisitos y carga privada de documentos reutilizan `DriverSetupPage` y el RPC existente. El portal muestra revisión/estado y, al aprobarse, ofrece el enlace de Play para la misma app oficial. Un trigger prepara el correo de aprobación a partir de cambios de estado hechos desde el administrador; la función Edge lo entrega con Resend e idempotencia. | Fuente preparada en PR #270. No desplegada. La publicación web requiere incorporar el commit al flujo autorizado; la migración y función Edge no se aplicaron. Antes de migrar hay que configurar el secreto de Vault `driver_approval_service_role_key`; para el correo, los secretos `RESEND_API_KEY` y `DRIVER_APPROVAL_EMAIL_FROM`, con el remitente verificado. OAuth Google debe permitir la redirección `https://expressviajes.online/?registro=conductor`. No hay envío de correos hasta desplegar/configurar la función y aplicar la migración. |

## 2026-10-23 — Evitar que el arranque espere antes del permiso GPS

| Fecha | Archivos | Operación | Impacto | Estado |
|---|---|---|---|---|
| 2026-10-23 | `lib/mobile_main.dart`, `lib/startup_permission_gate.dart` | Corregido | La solicitud de ubicación aparece antes de las verificaciones de entorno, cuota del mapa y estado de notificaciones. La consulta de cuota se ejecuta después en segundo plano; la verificación de cuenta/entorno sigue bloqueando el acceso operativo y ahora termina con opción de reintento tras 15 s, sin conceder acceso por timeout. Las llamadas nativas del gate GPS tienen límites de espera y muestran un error recuperable en lugar de dejar la pantalla girando. Aplica al arranque compartido de pasajero y conductor. | Cambio registrado en PR #270. Análisis y QA de arranque en emuladores pendientes; no se desplegó ni generó una nueva APK/AAB. |


## 2026-10-23 — Permiso de ubicación en segundo plano para conductor

- Al inicio, pasajero y conductor continúan solicitando solo ubicación “mientras se usa la app”.
- Al tocar “En línea”, Android comprueba el permiso real del sistema. Si falta “Permitir todo el tiempo”, Express muestra el motivo, ofrece abrir Ajustes y deja al conductor desconectado hasta que vuelva y toque “En línea” otra vez.
- La app consulta el permiso del dispositivo porque el servidor no puede leer directamente los permisos Android. Después de la comprobación local, el backend sigue validando aprobación y elegibilidad antes de activar al conductor.
- El scaffold Android oficial inyecta ahora `ACCESS_BACKGROUND_LOCATION` idempotentemente desde `.github/scripts/apply_floating_overlay.py`.
- Se añadieron aserciones de contrato para el permiso, la verificación previa a activar y el acceso a Ajustes. Guía y plan de QA: `docs/DRIVER_BACKGROUND_LOCATION.md`.
- GitHub: el gate de versión única y el inventario de cambios pasaron en SHA `93ab5cb987af4cd5264f145795e42ddc55d8221f`; el resto de checks seguían en ejecución al registrar esta nota.
- Aún no hay nueva build candidata instalada con este permiso, así que falta QA funcional de conductor/pasajero con el SHA final. No se cargó APK/AAB a Play ni se promovió a Producción.

## 2026-10-23 — Bloquear nuevas solicitudes con deuda de cancelación

- Diagnóstico confirmado en Supabase Production mediante lectura de la función activa y los triggers de `ride_requests`: `ride_requests_guard_cancellation_debt` se ejecuta antes de `trg_ride_zone_from_pickup`, pero el guard consultaba solo `NEW.zone_id`. En una solicitud nueva, la zona aún no estaba asignada; por eso la consulta de deuda no encontraba la deuda y permitía continuar.
- Se preparó la migración `20261023170000_fix_passenger_cancellation_debt_guard_zone.sql`. El guard ahora deriva la zona desde las coordenadas de recogida antes de consultar la deuda y bloquea de forma cerrada si una persona con deuda envía una solicitud sin zona resoluble.
- Se conserva el alcance por usuario, país, canal Preview/Producción y servicio Taxi. Envíos/paquetería y Delivery no se bloquean por esta deuda de Taxi.
- El mensaje del servidor dirige a “Pagos y billetera” sin revelar el proveedor. La migración anterior todavía contiene el texto antiguo; esta reemplaza la función activa cuando se aplique.
- Se añadió `test/cancellation_debt_guard_zone_contract_test.dart` para proteger el orden de resolución de zona, los filtros de seguridad, el comportamiento fail-closed y el mensaje neutral.
- Verificación de estado: la migración nueva **no figura aplicada** en Supabase Production. La función activa sigue mostrando el comportamiento anterior. No se creó ninguna solicitud o viaje de prueba.
- Pendiente: CI del commit final; aplicar la migración con aprobación explícita; después verificar un caso controlado de usuario endeudado en una cuenta QA Preview, sin generar viaje real en Producción.

### Estado final del parche de deuda — 2026-10-23

- Commit probado: `1930636f87ef744669620f4a986894c66ff70efb`; los 8 checks asociados finalizaron en **success**, incluida la prueba de contrato, la suite Flutter y el build Web.
- La migración `fix_passenger_cancellation_debt_guard_zone` se aplicó a Supabase Production y quedó registrada como versión `20261023071944`.
- Verificación posterior de solo lectura: la función activa deriva la zona desde el punto de recogida antes de consultar deuda, mantiene usuario/país/canal y solo bloquea Taxi; el trigger sigue siendo `BEFORE INSERT`.
- El texto del bloqueo ahora dirige a Pagos y billetera y no nombra proveedores.
- No generé viajes reales ni cambié deudas existentes. No se publicó APK/AAB ni se desplegó la web.

### Aviso duplicado al conductor por deuda — 2026-10-23

- Causa encontrada: el overlay compartido de transición mostraba “No se pudo completar” durante 850 ms y luego el manejador de aceptar oferta mostraba el mensaje específico de deuda. Una sola operación producía dos avisos consecutivos.
- El overlay genérico ahora se omite solo para rechazos reconocidos de deuda; el manejador mantiene el aviso accionable y la protección del servidor no cambia.
- Se añadió una prueba de contrato para deuda BOB y errores no relacionados.
- Pendiente: checks de GitHub y QA funcional en emulador. El cambio de app aún requiere una build nueva para llegar a los dispositivos; no se publicó APK/AAB ni se desplegó la Web.

### Tarifa visible para el pasajero en viaje activo — 2026-10-23

- La tarjeta del pasajero ahora muestra la tarifa acordada cuando hay conductor asignado o el viaje está en curso.
- Usa la misma fuente y precedencia que la tarjeta del conductor: `trips.final_fare`, con `ride_requests.proposed_fare` como respaldo, y la moneda del viaje.
- No recalcula ni modifica el precio; oculta la fila si no hay una tarifa válida.
- Pendiente: CI y revisión visual en emulador. No se desplegó ni publicó una build.

### Seguimiento del viaje sin estado repetido — 2026-10-23

- En `Seguimiento del viaje`, se retiró la línea de estado duplicada del encabezado. El panel inferior conserva el estado, la distancia y el ETA.
- La tarjeta activa de la pantalla principal sigue disponible; el botón “Mapa” abre la vista detallada.
- Pendiente: checks automáticos y revisión visual en emulador. No se desplegó ni publicó una build.
