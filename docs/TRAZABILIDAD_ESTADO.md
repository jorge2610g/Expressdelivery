# Trazabilidad de estado — Express (app)

Propósito: una sola línea de tiempo que avanza en un solo sentido. Lo antiguo no se borra; se marca con su estado final para que nadie reabra un error ya corregido ni dé por pendiente algo que nunca se hizo.

Fecha de corte: **2026-11-01**. Base de trabajo: `claude/express-desde-main-20261101` desde `main` `f4eac6b0` (1.6.6+158).

## Leyenda

- **HECHO**: está en `main` o en Google Play, y se comprobó.
- **SUPERADO**: reemplazado por trabajo posterior. **No reabrir**.
- **INCONCLUSO**: falta algo concreto. Se dice qué falta.
- **DECISIÓN**: requiere orden del propietario antes de actuar.
- **HISTÓRICO**: solo referencia.

## Estado vigente

| Tema | Estado | Referencia |
|---|---|---|
| Google Play Producción | 1.6.4 (156), confirmado por el propietario | Consola Play, 01-11 |
| Google Play Prueba interna | 1.6.6 (158), QA aprobado por el propietario el 01-11; lista para subir | Consola Play y confirmación del propietario, 01-11 |
| `app_release_gate` (Supabase) | HECHO el 01-11 por orden del propietario: Producción 156 (`production_build_id` = job `2539d879`, commit `f730034`), siguiente 159. Candidato de producción limpiado el 01-11 por orden del propietario (sin candidata pendiente). El job 156 sigue sin `promoted_build_id` en `android_single_app_candidates`: INCONCLUSO, sin efecto en el gate | Registrar la promoción en la tabla de candidatas solo con orden |
| Siguiente candidata | 1.6.7+159 (versión y build suben juntos); sin preparar | Orden del propietario |
| Notificación de ubicación del pasajero | HECHO en `main`: el flujo del conductor es el único que pide la notificación | `lib/connected_experience.dart` (`driverBackgroundTracking`) |
| Realtime del mapa en Web | HECHO (la confirmó el propietario); en Android, pendiente de prueba en teléfono | `00c05d2` |
| Selección de dirección por pin | INCONCLUSO: no se ha reproducido en la versión actual | Reproducir en web y en 158 |
| Demo Express Moto | Solo web (`/presentacion/`); no forma parte de la app Android | `express_moto_demo_widgets.dart` |

## Builds (historial de subidas)

| Build | Estado | Nota |
|---|---|---|
| 147–152 | HECHO | 152 fue la base de Producción hasta el 01-11 |
| 153 | SUPERADO | Subido a Internal; reemplazado por 154 y después por 158 |
| 154 | SUPERADO | Reemplazado en Internal |
| 155 | SUPERADO | Reemplazado en Internal |
| 156 | HECHO en Producción | Confirmado por el propietario el 01-11 |
| 157 | SUPERADO | Descartado: lo reemplazó 158 en Internal |
| 158 | HECHO en Internal | QA aprobado por el propietario el 01-11. Promoción a Producción: no autorizada todavía |

## Línea de tiempo de PRs abiertos (35)

### SUPERADOS — no reabrir

| Grupo | PRs | Motivo |
|---|---|---|
| Builds 138 y 141 | #110, #111, #254, #262, #266, #268, #267 | Build 141 nunca se publicó. La línea siguió con 147–158. |
| Planes sin compilar | #252, #253 | Documentos de órdenes ya cubiertas por builds reales |
| Era 141 (octubre 15–19) | #248, #249, #250, #259, #260, #261, #265 | Superados por `main` y las migraciones aplicadas. **#249 y #250 se verifican antes de cerrar** (ver DECISIÓN). |
| Octubre 2 | #15, #16 | Migraciones de suscripción y demanda aplicadas |
| Aislamiento | #65 | `strict_runtime_channel_isolation_and_admin_live_scope` aplicada |
| Octubre 9–10 (P0 y guards) | #144, #145, #146, #147, #150, #153, #154 | Migraciones con el mismo tema aplicadas. Verificar código antes de cerrar. |

### VERIFICAR antes de cerrar

| PR | Qué verificar |
|---|---|
| #80 | Anuncios de pasajero (`passenger_ads_controls` aplicada) |
| #172 | Vehículos explícitos y GPS (`parcel_vehicle_explicit_grants_preview_20261013`) |
| #190 | Premios de campeonato (`driver_championships` aplicada) |
| #199 | Servicios visibles por zona (`passenger_landing_selected_services_20261013` aplicada) |
| #202 | Pestañas de servicio del conductor (`driver_work_permissions_per_runtime_20261013` aplicada) |
| #256 | Ofertas flotantes (`native_push_floating_offer_device_optin_20261016` aplicada) |
| #100 | Load Lab en Producción (`audit_load_lab` aplicada) |

### DECISIÓN del propietario

| PR | Pregunta |
|---|---|
| #322 | Versión elegida para el candidato Android. Se decide junto con Admin #131. |
| #222 | Demanda en saltos de 0,5. El título dice «pendiente definir límite de tarifa». |
| #249 | Llamadas entrantes en segundo plano (ZEGO). No encontré equivalente en `main`. ¿Trabajo pendiente real? |
| #250 | Mapa visible en asignación. No encontré equivalente en `main`. ¿Trabajo pendiente real? |

## Trabajo pendiente no incorporado (no es superado)

Ramas que se conservan como historia. Su contenido **no está en main**, salvo el SQL de #145–#147 (PR #349); retomar solo como cambio aparte y con orden del propietario.

| PR | Estado | Qué falta en main |
|---|---|---|
| #265 | Cerrada sin fusionar | Barra de ofertas de 30 s y cierre por cambios del backend (4 líneas en `video_style_home.dart`). Decidir 15 s o 30 s primero. |
| #199 | Cerrada sin fusionar | Interfaz de selección de servicios en la portada (43 líneas en `connected_experience.dart`). La migración sí está en main. |
| #250 | Cerrada | 25 líneas de mapa en `video_style_home.dart`. El resto era QA APK, que la regla vigente prohíbe. |
| #144 | Cerrada sin fusionar | Guard de cobertura Preview: sin migración en main. |
| #145, #146, #147 | Cerradas sin fusionar | Sus migraciones ya están aplicadas en Supabase. Su SQL ya está en main gracias a la PR #349, fusionada el 01-11. |
| #154 | Cerrada sin fusionar | Migraciones `20261010130655` y `20261010143000` no aparecen en Supabase. Estado incierto. |
| #150 | Cerrada sin fusionar | Throttle de conductores: 14 % de sus líneas en main. |
| #153 | Cerrada sin fusionar | Guard de migraciones: 6 % de sus líneas en main. |
| #80 | Cerrada sin fusionar | Anuncios de pasajero: 8 % de sus líneas en main. |
| #100 | Cerrada sin fusionar | Load Lab: 40 % de la única línea en main. |
| #172 | Cerrada sin fusionar | Suite de conductor: 25 % en main. |
| #190 | Cerrada sin fusionar | Migración `20261012183500` no aplicada en Supabase. |
| #202 | Cerrada sin fusionar | Pestañas de servicio del conductor: 11 % en main. |
| #222 | Cerrada sin fusionar | WIP de demanda en saltos de 0,5. Pendiente de definir el límite de tarifa. |
| #248 | Cerrada sin fusionar | Fix de concurrencia del despliegue web: no está en main. |
| #249 | Cerrada sin fusionar | Llamadas entrantes en segundo plano (ZEGO): 10 % en main. |
| #322 | Cerrada sin fusionar | Versión del candidato Android: se decide junto con Admin #131. |

## Inconsistencias conocidas

1. **Migraciones con versión distinta en el repo y en Supabase** (archivo → versión aplicada): `20261026032432` → `20261026042837`; `20261026043600` → `20261026050049`; `20261026234131` → `20261026234434`; `20261027000500` → `20261027000558`; `20261031062041` → `20261031064126`. Estado: INCONCLUSO. Las migraciones aplicadas no se editan (AGENTS.md).
2. **Migración de Admin #137** (`20261028163325_operator_module_permissions.sql`) no aplicada. Pertenece a Admin, no a Express; se decide en Admin.
3. **`app_release_gate`** muestra un candidato 1.6.1/138 y Producción 152. Estado: INCONCLUSO.
4. **`Express_Repartidor`** existe como repositorio, aunque AGENTS.md dice que no debe haber una app separada. Estado: DECISIÓN.
5. **`Express-Oficina-IA`** tiene ramas remotas nuevas que no están en el clon local. Estado: pendiente de sincronizar.
6. **Rama antigua `claude/cool-faraday-yhh09s`** (`523731cb`): contiene 3 commits obsoletos de la notificación. Estado: HISTÓRICO; no usar como base.

## Cómo mantener este documento

- Cada cambio de estado se agrega como fila nueva con fecha; no se borra la anterior.
- HECHO solo con referencia verificable (commit, PR fusionada, migración aplicada o confirmación en Play).
- Antes de cerrar una PR, comprobar que su contenido no es más antiguo que `main`.
