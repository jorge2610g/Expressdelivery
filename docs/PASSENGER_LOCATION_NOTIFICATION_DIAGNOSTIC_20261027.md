# Express passenger mode: location notification diagnostic (2026-10-27)

## User report

The owner sent `SVID_20261027_013019_1.mp4` and reported that Express is in Passenger mode but Android appears to show the driver as active.

## What the video shows

- Express is displaying the passenger home: “¿A dónde vas?” with Inicio, Historial, Pagos and Perfil.
- The Android notification shade shows the persistent notification “Express · ubicación activa”.
- The notification text says location is kept current “mientras estás en línea o realizando un viaje”. It does not identify which mode started location tracking.

The video confirms a misleading location notification. It does not show an “online” control or prove that the driver account is online.

## Code cause

The passenger map starts `_startPassengerMapFollow()` from `lib/video_style_home.dart` during initialization. That subscribes to `ExpressLocationService.positionStream()`.

In `lib/location_service.dart`, Android `_trackingSettings()` always supplies a `ForegroundNotificationConfig`, including for the ordinary, low-frequency passenger map-follow stream. Android therefore displays the same ongoing location notification used for driver tracking.

The server-side mode-transition guard in `supabase/migrations/097_driver_mode_runtime_isolation.sql` sets `driver_profiles.online_status` to `offline` when `users.active_mode` changes away from `driver`, unless an active trip/delivery blocks the transition. The notification itself is not proof of driver-online state.

## Recommended fix

Separate location stream settings by purpose:
- Passenger map camera-follow while idle should use a foreground-only, low-power stream without an ongoing Android foreground-service notification.
- Preserve the foreground service notification for driver-online/background tracking and any active service that requires location tracking.
- Keep the existing active-service guards and mode-transition behavior; do not weaken backend driver isolation.

This requires a new Android app build to reach installed devices. No code change, Android build, or deployment for this notification issue has been made yet.

## Validation notes

When diagnosing this again, distinguish:
1. the visible app mode (passenger screen),
2. the Android foreground-location notification, and
3. the authoritative `driver_profiles.online_status` value.

Do not infer driver-online state from the notification alone.
