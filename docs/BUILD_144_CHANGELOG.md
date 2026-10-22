# Registro de cambios — Express Principal 1.6.3+144

Estado: **candidata en preparación; sin publicación en Google Play Producción**.

## Alcance del candidato

- App única oficial: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Versión `1.6.3+144`; APK y AAB deben salir del mismo SHA de fuente mediante el workflow oficial con Flutter 3.47.5.
- El AAB se destina únicamente a Google Play Internal y la APK firmada queda disponible para QA/emuladores.
- El cambio de cancelación incluido: el pasajero recibe la advertencia y el monto al cancelar después de que el conductor acepta; la espera y cuenta regresiva de cinco minutos corresponden solo al conductor después de “Ya llegué”.
- El cobro y la moneda siguen determinados por la configuración de cada zona. La corrección de cotización ya está aplicada en Supabase Production; esta build contiene el mensaje Flutter actualizado.

## Evidencia y límites

- Build 143 anterior en estado `ready`, SHA `e2ffce53293f3c339a0676fa75844c4e6ccd8b74`, workflow `39859205262`, cargada a Internal.
- Al iniciar esta preparación, Google Play Production seguía en código 141 y el contador siguiente figuraba en 143. Para el candidato 144 se requiere reservar el contador 144 sin promover 143 ni modificar el baseline Production.
- El gate se actualizará solo si el baseline continúa en 141, el contador es 143 y el job 143 está `ready`; se guardará respaldo previo y verificación posterior.
- No se publicará en Production ni se aprobará/promoverá automáticamente el candidato.
- Pendiente registrar SHA de fuente final, UUID del job 144, resultado de CI, hashes APK/AAB y estado real de Play Internal después de completar el flujo.
- Las revisiones de GitHub mantienen recuperable el contenido previo de `pubspec.yaml` y del test de contrato.
