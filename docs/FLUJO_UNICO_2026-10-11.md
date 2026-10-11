# Flujo único de Express · 2026-10-11

Este documento es la referencia de trabajo. Prevalece sobre cualquier documento anterior que diga otra cosa.

## 1. Una sola aplicación
- Una app Android: `com.express.usuario1`. Se entrega como **APK y AAB del mismo código** de `main`.
- Una web: `expressviajes.online`, publicada desde `main`.
- **No existe** app paralela, ni build de QA con otro paquete, ni flujo de APK Preview separado.

## 2. Preview y Producción son canales de datos, no apps
- Preview y Producción comparten la misma base de Supabase: `zgpijrznvaskgcmauwxx`.
- El canal decide qué datos se leen y escriben (`p_channel`), no qué app se instala.
- El proyecto `xbphilqezmwfjfpdbwad` **ya no se usa**.

## 3. Una sola compilación y una sola trazabilidad
- Un commit de `main` → un APK y un AAB con el mismo `versionCode`.
- `versionCode` = `production_store_build_number + 1` (tabla `app_release_gate`, plataforma `android`).
- Ningún build se compila con otro paquete ni con otro entrypoint.

## 4. Contador de Google Play (registro)
| Fecha | Campo | Antes | Después | Motivo |
|---|---|---|---|---|
| 2026-10-11 | `production_store_build_number` | 137 | 138 | El propietario confirmó que Play ya tiene el build 138. |
| 2026-10-11 | `next_production_build_number` | 138 | 139 | Siguiente build a compilar. |

Para revertir: `UPDATE public.app_release_gate SET production_store_build_number=137, next_production_build_number=138 WHERE platform='android';`

## 5. Pasos para publicar un build
1. Cambio en `main` (PR revisada y CI en verde).
2. El propietario, desde el panel de Producción, crea el candidato (`admin_queue_single_app_candidate`).
3. Se compila el APK y el AAB de `com.express.usuario1` del mismo commit.
4. Prueba del APK por el propietario.
5. Subida del AAB a Google Play **solo con orden expresa del propietario**.

## 6. Regla de documentación (permanente)
Todo cambio, en código o en base de datos, se documenta **en el repositorio** en el mismo cambio: qué se cambió, valores anteriores, cómo revertirlo y quién lo autorizó. Así cualquier persona o IA puede reconstruir el estado.

## 7. Documentos anteriores
Los documentos de auditoría y de releases anteriores son **históricos**. Cuando contradigan este documento, prevalece este.
