# Registro de cambios — Express Principal 1.6.3+143

Estado: **candidata preparada en el PR #270; compilación pendiente**.

## Motivo
El propietario solicitó pasar a `versionCode=143` porque indicó que Google Play ya no aceptará el 142. Esta razón viene de la solicitud del propietario; no se verificó de forma independiente en Play Console.

## Fuente y cambios
- Continúa la única aplicación oficial: `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Versión en `pubspec.yaml`: `1.6.3+143`.
- Actualizada la prueba de contrato para exigir que el código fuente y la candidata declaren `1.6.3+143`.
- Se conserva la funcionalidad de cobros zonales de cancelación del PR #270 y la configuración actual por zona/canal.
- No se compilaron artefactos todavía, no se instaló APK, no se cargó AAB a Google Play y no se publicó en Producción.

## Pendiente para generar artefactos
1. Validaciones de GitHub Actions aprobadas para el SHA final de la candidata.
2. Encolar el job oficial `single-app-candidate-apk+aab` ligado al SHA final.
3. Ejecutar el workflow Android oficial, fijando Flutter 3.47.5, `lib/mobile_main.dart`, paquete oficial y overlay nativo; APK y AAB deben compartir commit, versión e identidad.
4. Confirmar los hashes del APK y AAB.

El módulo de compilación de Adminexpress actualmente está limitado a `versionCode=142`; requiere permitir 143 y el acceso de una cuenta con el módulo `Builds` para crear el job autorizado. La compilación queda bloqueada hasta completar ese paso.
