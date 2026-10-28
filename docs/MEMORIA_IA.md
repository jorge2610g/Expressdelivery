# Memoria IA — Express Delivery (Expressdelivery)

Leer esto antes de tocar nada. Actualizado: 2026-10-28.
Reglas superiores: `AGENTS.md`. Parte compartida con Admin: `Express-Oficina-IA/docs/MEMORIA_COMPARTIDA.md`.

## 1. Qué es
- App de pasajero y conductor: Taxi, Envíos y Delivery cliente.
- Android oficial: paquete `com.express.usuario1`, entrypoint `lib/mobile_main.dart`.
- Web de clientes: `https://expressviajes.online/` (entrypoint `lib/web_main.dart`).
- Backend compartido con Admin (Supabase `zgpijrznvaskgcmauwxx`).
- Preview y Producción no son apps distintas: el backend decide el contexto según la cuenta que entra.

## 2. Estado actual
- `main`: versión `1.6.4+152`.
- Google Play Producción: 1.6.4 build 152 disponible para todos (handoff 2026-10-27; confirmado por el propietario el 2026-10-28).
- Dirección al elegir en el mapa: **resuelto** en 152 (confirmado por el propietario).
- Pendiente: aviso «ubicación activa» que aparece en modo pasajero. La app usa el GPS en primer plano con notificación de servicio de conductor. La corrección propuesta (GPS sin notificación para pasajero, rastreo en segundo plano solo para conductores) **no está aplicada**.
- Pendiente de verificar: el handoff del 27-oct menciona otros temas; revisar antes de actuar.

## 3. Cómo se publica
- **Web:** `deploy-web.yml` compila `lib/web_main.dart` y publica en `expressviajes.online`.
- **Android, pruebas internas:** workflow `build-android.yml`. Sube AAB a Google Play Internal solo con confirmación: frase `AUTORIZO APK+AAB PRUEBAS INTERNAS` más el `job_id` de la cola. También puede dispararse al cambiar `.github/build-requests/android-internal.json` en `main`, desde la cuenta del propietario. Usa el secreto `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
- **Android, producción:** NO sale de estos flujos. Subir o promover a Producción requiere una orden separada del propietario.
- **Sincronización de Producción:** `sync-play-production.yml` lee el track de producción cada 15 min. Es solo lectura: no sube ni publica nada.
- **Actualización obligatoria y avisos a usuarios:** se configuran en Admin. No activar sin orden expresa.

## 4. Qué NO tocar sin orden
- No cambiar código ya publicado en 152 ni sus workflows de publicación.
- No subir Android a Play, ni promover, ni activar actualización crítica, ni enviar avisos.
- No crear otra app ni otro paquete. Solo `com.express.usuario1`.
- No mezclar datos de Preview y Producción. Respetar RLS y RPC.
- No editar ni volver a ejecutar migraciones ya aplicadas. Crear migraciones nuevas.
- No poner secretos, claves ni JSON de cuentas de servicio en Git o en el chat.

## 5. Abierto y cerrado
- **Abierto:** aviso de ubicación del pasajero (sección 2).
- **Abierto:** dos cuentas de servicio de Google Play. Se creó `play-publisher` desde Chrome con permiso de producción. El secreto del repositorio usa `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. No está confirmado qué cuenta contiene ese secreto. Pendiente: confirmar con el propietario y quitar el permiso de producción si no se necesita.
- **Cerrado:** dirección al elegir en el mapa (152).

## 6. Trazabilidad de PRs (actualizada 2026-10-28)
Fuente: lista de PRs abiertas y cerradas de GitHub. Un PR «cerrado» aquí no se borra; solo deja de ser trabajo activo.

**Cerrado y publicado**
- #328 a #342 (26–28 oct): corrección de direcciones, sincronización de Play, handoff operativo y presentación Express Moto. Incluidos en `main`, y la versión 1.6.4+152 los usa.

**Activo: decidir antes de tocar**
- #322 (abierto, no borrador, 26-oct): honrar la versión seleccionada en candidatos Android. Relacionado con el flujo de build. Decidir si entra o se cierra. No mezclar con la 152.

**Seguridad P0 pendiente de confirmar (9-oct, sin fusionar)**
- #144, #145, #146, #147: guardas para que las pruebas (Preview) no cambien cobertura, tarifas ni canales de zonas reales. Antes de cerrarlos, confirmar en `main` si la protección ya existe por otra vía. No ignorarlos: afectan a datos reales.

**Históricos (QA de build 138 a 141 y pruebas antiguas)**
- Sustituidos por el flujo de versión única y por 151/152: #110, #111, #248, #249, #252, #253, #254, #256, #259, #260, #261, #262, #265, #266, #267, #268, #250.
- Acción propuesta: confirmar con el propietario y cerrar. No retomarlos sin orden.

**Pendientes de decisión (abiertos sin borrador, de octubre)**
- #150, #153, #154 (10-oct): rendimiento de conductores, guardia de migraciones y zonas/activación manual de conductor. Verificar en `main` antes de cerrar.
- #199 (13-oct): servicios visibles por zona desde Admin.

**Borradores de funciones (sin fusionar)**
- #15, #16 (2-oct), #172, #190, #202, #222: suscripciones, tarifa por demanda, pestañas de servicio para conductores, premios de campeonato. Retomar solo con orden.

## 7. Registro de sesiones de IA (obligatorio)
Cada IA que entre o cambie algo añade una entrada al final:
- **Fecha y hora de entrada**, y qué se va a revisar.
- **Qué cambió:** archivos y motivo.
- **Qué NO cambió:** lo que se revisó y se dejó igual.
- **Pruebas:** qué se probó, sobre qué commit, con qué resultado. Si no se probó, decirlo.
- **Despliegues y publicaciones:** qué se subió, a dónde y con qué versión. Si no hubo, escribir «sin despliegue».
- **Qué quedó abierto** y cuál es el siguiente paso.

### Entradas
- **2026-10-28 · Creación de esta memoria.** Cambió: `docs/MEMORIA_IA.md` y `CLAUDE.md` (ahora apunta aquí). No cambió: código, workflows, `main`, Play, Supabase. Pruebas: no aplica (solo documentación). Despliegues: ninguno. Abierto: aviso de ubicación del pasajero; cuenta de servicio de Play por confirmar.
- **2026-10-28 · Auditoría de PRs y alineación de memoria (segunda pasada).** Cambió: sección de trazabilidad de PRs en esta memoria y entrada de registro. No cambió: código, workflows, `main`, PRs (no se cerró ni fusionó ninguno), Play, Supabase. Pruebas: no aplica (solo documentación). Despliegues: ninguno. Abierto: decisión del propietario sobre los PRs de la sección 6; confirmar en `main` los P0 de seguridad #144 a #147 antes de cerrarlos.
