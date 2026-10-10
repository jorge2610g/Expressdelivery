# [SPEC] Arquitectura de UI de pasajero inspirada en dos referencias de video

> Autor: Claude (arquitecto/revisor). Implementación: IA programadora. Claude no programa.

## Referencias analizadas (2026-10-10)
Dos grabaciones de TikTok de tutoriales Flutter (fotogramas cada 4 s). Son contenido
de terceros: **no copiar** marca, ilustraciones, fotos de autos, textos ni nombres.
Se toma solo la estructura de flujo:
1. Splash con logo → login con "Welcome back", campo de correo, contraseña, "mantener sesión",
   botón principal, acceso con Google/Apple.
2. Home de viaje: tarjeta de promoción, lista de servicios con precio y tiempo, botón de reserva.
3. Verificación de código (OTP) → **NO aplica**: el OTP por SMS está retirado; no reactivar.
4. Billetera: tarjeta de saldo y lista de movimientos recientes.

## Objetivo
Diseñar la capa visual de pasajero sobre la arquitectura actual de Express, reutilizando
datos y reglas existentes, sin cambios de backend.

## Fuera de alcance
- Migraciones, RPC nuevas, RLS, Edge Functions, despliegues.
- Verificación OTP/SMS y Didit (retirados).
- Imágenes o assets de terceros; usar iconografía propia o existente.
- Categorías de vehículo ficticias: los servicios vienen de `service_catalog`/`zone_service_catalog`.

## Arquitectura propuesta (dentro de `lib/`)
- `lib/ui/passenger/home/` — pantalla de viaje: tarjeta de destino, lista de servicios
  alimentada por el catálogo existente y precio solo tras la cotización del servidor.
- `lib/ui/passenger/services/` — tarjeta de servicio (nombre, icono, ETA, precio cotizado).
- `lib/ui/auth/login/` — reutiliza el flujo de `auth_entry.dart` (correo, Google, Apple);
  no agrega pantallas de código.
- `lib/ui/wallet/` — tarjeta de saldo y lista de movimientos leídos de `wallet_accounts` /
  `wallet_transactions` mediante los servicios existentes (solo lectura).
- Componentes compartidos: reutilizar `express_motion.dart` y los tokens de color/tipografía
  existentes; no crear un sistema de diseño paralelo.

## Reglas obligatorias
- Precio: nunca mostrar un monto local por defecto; esperar la cotización del servidor.
  Estados: cargando (sin confirmar), error con botón "Reintentar", éxito. Ver `CHANGELOG_ACTIVE.md` 2026-10-08.
- Mensajes de error: texto amigable; nunca excepciones crudas ni URLs internas.
- Preview y Producción usan el mismo código; el canal lo decide el runtime, no la UI.
- Animaciones: respetar `disableAnimations` del sistema.
- Layout: funcionar en 320×560 y con texto grande (ver `test/express_journey_dialog_test.dart`).

## Criterios de aceptación
- A) Ninguna pantalla nueva muestra OTP, SMS, Didit ni imágenes de terceros.
- B) Los precios salen solo de la cotización; con la cotización fallida se ve "Reintentar".
- C) `flutter analyze lib` 0 errores; `flutter test` pasa.
- D) Pruebas de layout en 320×560, 412×915 y texto grande.
- E) Capturas en Preview del home, login y billetera (evidencia manual del propietario).

## Riesgos
- Cambiar login puede afectar el registro de conductores: no tocar el flujo de conductor.
- Billetera: solo lectura; cualquier cambio de saldo queda fuera.

## Rollback
Revertir el commit (solo Dart/UI).

## Documentación
`docs/CHANGELOG_ACTIVE.md` y `docs/AI_HANDOFF_2026-10-10_SECURITY_AUDIT.md`.
