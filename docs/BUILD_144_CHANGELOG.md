# Registro de cambios — Express Principal 1.6.3+144

## Estado vigente y guía de continuidad — 2026-10-23 (actualizado)

Esta sección es la fuente operativa actual y sustituye el estado que sigue más abajo, conservado como historial.

- **Código:** PR [#270](https://github.com/jorge2610g/Expressdelivery/pull/270) está integrado en `main`. El seguimiento [#274](https://github.com/jorge2610g/Expressdelivery/pull/274) permanece en borrador hasta cerrar CI y publicación. Su fix final explicita `permissions: []` durante la sincronización de sesión ZEGO; la app solicita micrófono antes de una llamada saliente, no al abrir el inicio.
- **Validación automatizada:** con Flutter 3.47.5, suite completa **409/409 PASS**; prueba focalizada de permisos **2/2 PASS**; análisis de `lib/private_voice_call.dart` y su prueba: sin hallazgos; `git diff --check` pasa. Estos resultados incluyen el fix local que debe empujarse para disparar checks de GitHub.
- **Emuladores:** `emulator-5554` (API 37) muestra la pantalla de conductor con mapa y viaje activo; `emulator-5556` (API 34) muestra el flujo pasajero con mapa, conductor en camino, tarifa Bs 5,50, PIN y Waze. Ambos muestran Express 1.6.3+144 y preservan la sesión/datos. El log de ZEGO en 5556 confirma `permissions:[]`; no se mostró aviso de micrófono al iniciar. La revisión visual no aceptó ni canceló viajes.
- **Mapa:** los dos mapas cargaron teselas durante esta ronda. Las vistas de seguimiento descartan la respuesta `direct` como geometría y solo pintan línea vial cuando llega una ruta real. La línea recta observada primero en la captura es compatible con el resultado transitorio de una versión anterior mientras se resuelve la ruta; en las pantallas de seguimiento actuales no se debe mostrar esa línea como ruta. La carga depende de red/servicio de rutas. Se mantiene el proveedor/cupo actual, sin gasto ni loader nuevo.
- **Cambios funcionales previos:** el bloqueo Taxi por deuda, los avisos de cancelación por zona, el texto único de deuda al conductor, la tarifa del viaje para pasajero, el botón Waze, el registro web directo y la configuración de comisión por zona/servicio pertenecen al alcance fusionado de #270 y su backend ya anotado en las secciones históricas. La QA de esta ronda no crea cuentas, viajes, deudas ni pagos reales; por eso no certifica transacciones en vivo.
- **Web:** comprobar tras integrar #274 que el dominio oficial conserva el inicio normal de pasajero en `/` y que `https://expressviajes.online/registro/conductor` abre la ruta directa. El portal no debe ofrecer modo conductor. No crear cuentas ni enviar formularios de registro reales. La pantalla de correo de aprobación sigue pendiente por decisión del propietario.
- **Publicación:** el APK local es solo build debug temporal, con el paquete oficial y mismo certificado que los AVD; no es un APK/AAB de distribución. El PR necesita nuevos checks tras el push y luego el deploy automático de la web. Solo después de validar la URL pública y el SHA Android final, seguir el gate de Google Play y cargar la AAB a Pruebas internas. No promover a Producción.
- **Protecciones:** no ejecutar migraciones históricas, no configurar correo, no aumentar gasto de mapas y no modificar datos reales durante QA. App Android única `com.express.usuario1`, Web oficial de clientes `https://expressviajes.online/` y Admin Express único.

Estado actual: **409/409 pruebas y dos emuladores verificados visualmente; PR #274 aún necesita el commit del fix ZEGO, CI nuevo y comprobación final del registro Web desplegado. Sin build oficial, sin carga a Play y sin publicación a Producción.**

## Historial sustituido: estado anterior — 2026-10-23

Esta sección es la referencia actual. Las notas posteriores son historial cronológico y quedan sustituidas cuando una verificación más reciente lo indica.

- **Código fuente:** PR [#270](https://github.com/jorge2610g/Expressdelivery/pull/270), rama `work/express-single-app-1.6.3-build142`, abierto en borrador. El último SHA validado por CI es `5836429d09a8d8b1928c2c2d2fc2856d15d09eef`; la corrección de fallback para enlaces directos de GitHub Pages está incluida. El cambio funcional del mapa está en `227559baa0af0be8602d62b321cb9a53896f8a0b`; `71cd2d1` y `0be1240` son seguimientos documentales. El checkout del usuario se dejó intacto.
- **Cambios que se están validando:** control de reajuste de cámara para no cancelar continuamente la descarga de teselas; las rutas de viaje ya no pintan una línea recta provisional ni presentan la línea directa del proveedor como ruta vial. Los marcadores y el mapa base siguen visibles mientras se intenta obtener una ruta. No se añade un proveedor pago.
- **Pruebas:** la suite completa pasó con **406/406** después del cambio de rutas; las pruebas focalizadas de mapas, cámara, ofertas, GPS y permisos también pasaron. `git diff --check` pasó. `flutter analyze` no reportó errores; el proyecto conserva lint `info` existentes. `flutter build web --release --target lib/web_main.dart` compiló correctamente (el dry run WASM informa incompatibilidades de Zego ya existentes; no afecta al bundle JS oficial).
- **Android:** APK debug temporal `com.express.usuario1` 1.6.3+144 compilada. El certificado SHA-256 `5f31561b6133b572b9f93fd05a0c914916f29edaa7d9e72c84ad37bf9d3313eb` coincide con ambos AVD. `install -r` terminó con éxito en 5554 y 5556, sin borrar datos. La captura actual de 5556 muestra calles, conductor en camino, tarifa Bs 5,50, PIN y Waze; el mapa no dibuja una línea recta provisional. La geometría vial no llegó y no aparece una ruta, por lo que queda validada la supresión del fallback ficticio, no la disponibilidad de una ruta vial. No se pulsaron acciones que cambien el viaje. QA del perfil Android 17/API 37 queda inconclusa: 5554 registró ANR de servicios del sistema mientras Express consumía entre 69% y 102% de CPU; luego `system_server` se reinició. El AVD original quedó pausado, con overlay temporal preservado. Una segunda instancia limpia del mismo perfil (5558) tuvo ANR de `SystemUI` durante su primer arranque, antes de iniciar Express. Se actualizó Express en esa instancia con `install -r`; la firma coincidió, la cuenta existente se conservó y no se envió ningún formulario. Tras abrir Express, el proceso llegó a 41–59% de CPU junto con alta carga de `system_server` y `SystemUI`; no se observó crash de Express, pero la captura volvió a expirar y no se pudo validar visualmente el flujo. Esto no permite atribuir la causa solo a la app o al emulador. Ambos procesos API 37 quedaron pausados para evitar seguir saturando el host. El AVD API 34 (5556) sigue respondiendo; la app se mantiene en 2,3% de CPU y muestra el viaje de prueba con tarifa y Waze. No subir Android a Play Internal hasta completar la QA pendiente del perfil API 37.
- **Mapa y costo:** el servicio OSRM público respondió para una ruta de prueba en Trinidad, Bolivia, con geometría vial. Es una comprobación de conectividad desde el equipo, no una garantía de respuesta desde cada dispositivo. Mapbox sigue sujeto a su cuota existente; no se habilitó ni añadió gasto. Si ningún proveedor entrega geometría, se mantienen los pines/mapa sin una línea recta engañosa.
- **Registro Web:** prueba visual local en `lib/web_main.dart`: `/registro/conductor` y `/?registro=conductor` muestran “Regístrate para conducir”, con correo/contraseña y Google; “Ya tengo cuenta” abre el acceso con correo/contraseña, Google y recuperación de contraseña. La ruta normal `/` muestra acceso normal y la lectura del código confirma que la experiencia Web fuerza `passenger`, ignora eventos de conductor y oculta el selector de modo. No se crearon cuentas ni se enviaron formularios; aprobación en tiempo real no se pudo probar sin una cuenta de QA. Verificación pública actual: `/` responde 200, pero `/registro/conductor` responde 404 de GitHub Pages. El workflow incluye la copia del `index.html` a `build/web/404.html` para permitir rutas directas; el check de producción del commit `5836429` pasó. Falta integrar y desplegar, y confirmar la ruta con HTTP 200 en el dominio oficial. El correo de aprobación continúa deliberadamente pendiente.
- **CI más reciente:** el run `39933647359` para SHA `5836429d09a8d8b1928c2c2d2fc2856d15d09eef` terminó en éxito; suite Flutter, análisis, build web de producción y portal independiente pasaron. Los demás checks requeridos del PR también estaban verdes en la última revisión. Esto no reemplaza la QA visual pendiente en 5554 ni autoriza por sí solo la carga a Play.
- **Deuda y cambios previos:** la migración de bloqueo de nuevas solicitudes Taxi por deuda está aplicada en Producción como `20261023071944`; alerta duplicada del conductor, tarifa visible para pasajero, navegación Waze, inicio/GPS, registro Web y comisiones forman parte de las modificaciones previas de PR #270. QA no crea viajes ni deudas reales.
- **Supabase Production:** el inventario de migraciones confirma aplicadas las migraciones de tarifa de cancelación, deuda, comisión por zona y registro web con selección manual de zona; la barrera Taxi por deuda aparece como versión `20261023071944`. La migración separada para correo de aprobación (`20261023120000`) sigue sin aplicar, por decisión expresa del propietario. No es necesaria para la pantalla de estado ni para reenviar documentos; no habilitar correo.
- **CI y publicación:** los ocho checks de código del SHA `227559b` y los seguimientos documentales `71cd2d1` y `0be1240` pasaron, incluido Shared Flutter checks and production-format Web. Se agregó una corrección nueva al workflow para el 404 de GitHub Pages; todavía requiere commit, CI y despliegue. El PR sigue abierto en borrador. No se ha fusionado el PR, desplegado la Web, generado la build oficial firmada 144 ni subido APK/AAB a Play Internal. No promover a Producción.
- **Próximos pasos obligatorios:** subir el fallback 404 y pasar los checks nuevos; recuperar y completar la QA visual de 5554, y cubrir roles pasajero/conductor sin acciones que creen viajes o deudas. Luego integrar y verificar en `https://expressviajes.online/` que `/registro/conductor` abre el formulario mientras `/` conserva el acceso normal. Después usar el gate oficial de versión 144 para generar APK/AAB desde un SHA único y cargar la AAB a Pruebas internas. Si falta el job autorizado, resolverlo desde Admin Express, nunca insertar filas directamente. Dejar email pendiente y no promover a Producción.
- **Reglas:** una app Android oficial `com.express.usuario1`, una Web oficial de clientes `https://expressviajes.online/` y una sola consola administrativa. Las pruebas no deben cambiar datos reales ni separar Preview como producto o binario.

Estado: **406/406 pruebas pasaron; los checks previos están verdes y los cambios nuevos del fallback 404 están en validación. El portal local quedó validado a nivel visual sin enviar datos, pero producción confirma 404 en la ruta directa. La prueba en 5556 confirmó mapa/tarifa/Waze, pero no obtuvo geometría vial; 5554 sigue con ANR del emulador y sin QA visual. No fusionado, sin despliegue oficial, sin build de release ni carga a Play Internal.**

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
- Estado histórico al redactar esta nota: la migración aún estaba pendiente y no se había creado una solicitud de prueba. La actualización posterior de este mismo documento registra que se aplicó en Supabase Production como versión `20261023071944` y describe la verificación de solo lectura. La validación funcional con una cuenta QA sigue siendo necesaria; no crear viajes reales en Production.

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
- Checks del head `a9008d59f8a236ff6a15c0b5ee92fcae806b6800`: los ocho workflows terminaron en success. Sigue pendiente confirmar visualmente este caso en la build exacta; no se publicó APK/AAB ni se desplegó la Web.

### Tarifa visible para el pasajero en viaje activo — 2026-10-23

- La tarjeta del pasajero ahora muestra la tarifa acordada cuando hay conductor asignado o el viaje está en curso.
- Usa la misma fuente y precedencia que la tarjeta del conductor: `trips.final_fare`, con `ride_requests.proposed_fare` como respaldo, y la moneda del viaje.
- No recalcula ni modifica el precio; oculta la fila si no hay una tarifa válida.
- CI del head vigente pasó; sigue pendiente la revisión visual del monto en la build exacta. No se desplegó ni publicó una build.

### Seguimiento del viaje: ajuste temporal revertido — 2026-10-23

- Se probó retirar el estado repetido del encabezado de `Seguimiento del viaje`, pero el usuario indicó que la pantalla debía quedar como estaba.
- El cambio se revirtió: el encabezado conserva su línea de estado, y el panel inferior sigue mostrando estado, distancia y ETA. La pantalla interna permanece disponible; la acción de la tarjeta principal es la que abre Waze.
- No atribuir la eliminación del estado repetido a la versión vigente.

### Navegación externa del pasajero — 2026-10-23

- La acción “Mapa” de la tarjeta del viaje activo del pasajero ahora se presenta como “Waze” y abre la navegación externa.
- Antes de recoger, Waze recibe el punto de recogida; durante el viaje, recibe el destino. Si la app no está instalada, se intenta abrir el enlace web.
- Se conserva intacta la pantalla interna “Seguimiento del viaje”, incluida su línea de estado en el encabezado.
- Pendiente la revisión visual de Waze en la build exacta. No se desplegó ni publicó una build.


### Ruta vial en el mapa: diagnóstico — 2026-10-23

- En la tarjeta de viaje activo, `_expressRoadRoute(from, to)` entrega inicialmente los dos extremos como una línea de respaldo y luego intenta obtener la geometría vial con `ExpressMapProvider.drivingRoute`. Al llegar la respuesta, sustituye la recta por la ruta; si la consulta falla o no devuelve puntos, queda el segmento recto.
- En `lib/service_tracking.dart`, la página dedicada `Seguimiento del viaje` construye `routePoints` con solo la posición del conductor y el destino actual. El código revisado no solicita una ruta vial desde esa página, por lo que allí la línea puede permanecer recta.
- Diagnóstico solamente: no se cambió la estrategia de mapas ni se añadió loader, proveedor o gasto. Pendiente decidir e implementar una ruta vial consistente en seguimiento, preservando el fallback actual y evitando destellos blancos.
