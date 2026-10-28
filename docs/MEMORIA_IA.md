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

## 6. Ramas y PRs (28-oct)
- Drafts antiguos #256 a #268 (16–19 oct): históricos. No retomar sin orden.
- #322 (26-oct): versión seleccionada para candidatos Android. Revisar antes de tocarla.
- La PR #250 ya no es la referencia: está muy por detrás de `main`.

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
