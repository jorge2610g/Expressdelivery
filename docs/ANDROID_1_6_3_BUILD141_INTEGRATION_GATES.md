# Express Android 1.6.3+141 — control de integración y salida

**Estado: EN DESARROLLO; NO COMPILADO; NO APTO PARA GOOGLE PLAY.**
**Rama de trabajo:** `work/express-unified-android-build141`.
**Base inicial:** `95e22e273d11de03846c928cbdea02542d5e9019` (`main`).
**Paquete único:** `com.express.usuario1`; **entrypoint:** `lib/mobile_main.dart`.
**Base única:** Supabase Express; cuentas de prueba identificadas por servidor, no por una segunda APK.

## Punto de partida (15-10-2026)

- El propietario presentó captura de **Google Play Console** que muestra **140 (1.6.1) en Producción al 100 %** (14-10-2026). El registro interno `app_release_gate.production_store_build_number=139` y `next_production_build_number=140` está DESACTUALIZADO y requiere conciliación con Play Console antes de poner en cola una build nueva.
- El paquete QA `1.6.2+140` del commit `95e22e27` fue instalado físicamente por el propietario: reportó que las mejoras esperadas no se ven. No reutilizar el contador 140 ni prometer que un build correcto incorpora todos los requerimientos.
- Hubo una compilación histórica con contador 141 y nombre `1.5.96` del 05-10-2026: **NO es la próxima compilación oficial** y no debe confundirse con la nueva versión `1.6.3+141`.
- Esta rama ya integra código Android de llamadas (PR #249) y ofertas flotantes/mapa/offline (subconjunto de PR #250), **sin prueba Android real ni APK**. Mantenerlo fuera de `main` hasta revisión y QA.

## Bloqueos de integración que deben cerrarse antes de compilar

1. **Ventana flotante de ofertas para conductor (P0):** se incorporó el puente Kotlin nativo versionado de PR #250 (no usa `flutter_overlay_window`) y la declaración `SYSTEM_ALERT_WINDOW` de PR #249 en el workflow oficial; pendiente probar que el plugin compile y que la ventana se muestre/oculte correctamente. La acción Aceptar devuelve al flujo habitual y revalida en backend; no da aceptación automática. Respeta permisos especiales de Android y restricciones de publicación. No activar en clientes reales hasta QA. La configuración actual `app_settings.driver_floating_offer_enabled` es false.
2. **Llamadas ZEGO (P0):** código de PR #249 trasladado a rama 141; probar flujo completo, permisos en Android real y revisión de Play. Confirmar FCM de ZEGOCLOUD, `ZEGO_RESOURCE_ID` configurado mediante Secrets, pop-up y audio real en Android abierto, segundo plano y bloqueado. `USE_FULL_SCREEN_INTENT` para llamadas es diferente de `SYSTEM_ALERT_WINDOW` para ofertas. No confundir haber compilado con haber recibido llamadas.
3. **Mapa y conexión de conductor (P0):** código de mapa y desconexión seleccionado de PR #250 integrado en rama; comprobar pruebas de mapa visible en asignación, estado desconectado, ofertas, reanudación y push. Mantener una sola bandeja Taxi/Envíos sin reintroducir pestañas por servicio.
4. **Cliente Taxi y Envíos (P0):** pantalla y paso a paso pactados, edición de precio, servicio/vehículo autorizado, multiplicador mostrado correcto, GPS, historial y ofertas en zonas reales y aisladas.
5. **Portada y Delivery cliente (P0/P1):** con 1 módulo disponible se entra directamente y con 2/3 se ve portada; banners por zona, nombres visibles Restaurantes/Delivery, catálogo, carrito, checkout, cupones, Express Plus y seguimiento. La disponibilidad comercial y los comercios visibles están sujetos a la zona/cuenta, no a si una APK fue construida con etiqueta «Producción». No activar compras reales ni alterar permisos automáticamente.
6. **Backend y aislamiento (P0):** una base, una APK, dos clases de identidad/datos; QA no recibe ofertas de Producción ni viceversa. Probar RPC/RLS de zonas, tarifas, usuarios, conductores, pedidos y notificaciones. Mantener funcionamiento de viajes reales.
7. **Panel Admin (P1, despliegue independiente):** auditar cambios UI de administración y controles por zona; el panel web NO queda actualizado por producir una APK cliente.
8. **Apps Express Comercio y Express Repartidor (P1, entregables separados):** el software de estas apps no forma parte del binario Express Principal. No declarar ambas completas por lanzar la versión 141 principal.

## Verificaciones obligatorias

- Flutter analyze, tests y build Android desde el SHA final exacto, además de regresión de Taxi real; validar permisos del **manifest fusionado resultante**, no solo el código.
- Pruebas físicas en dos Android: ofertas flotantes (switch apagado/encendido, permiso concedido/revocado, offline, aceptada, rechazada y expirada), llamadas en pantalla, segundo plano y bloqueo, GPS, notificaciones, modo pasajero/conductor, Preview/Producción por cuenta.
- Reconciliar metadatos de Play Console en `app_release_gate` **solo con aprobación y comprobaciones adecuadas**; el contador siguiente debe ser **141**.
- Los únicos binarios candidatos son **APK y AAB 1.6.3+141** firmados para `com.express.usuario1`, con commit SHA, hashes SHA-256 y GitHub Actions run documentados.
- `.github/workflows/build-android.yml` es manual; exige trabajo de compilación autorizado, SHA coincidente y frase `AUTORIZO APK QA`. No inventar enlace de descarga ni disparar Google Play sin aprobación adicional.
- No crear un segundo APK/bundle «Preview». La misma app reconoce el canal por cuenta.

**Regla de salida:** hasta que TODOS los controles P0 aplicables hayan pasado, el estado continúa **NO LISTO**, aunque el contador ya diga 141.
