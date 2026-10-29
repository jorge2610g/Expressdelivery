# Current operational handoff — Express (2026-10-27)

This is the current operational snapshot for the next engineer or AI. It replaces older progress messages and release counters as a status source. Owner-approved architecture and security rules in `AGENTS.md` remain in force. Older design proposals and “deploy still running” chat updates are historical; verify live state before acting.

## Android release and Play synchronization

Last verified on 2026-10-27 around 00:06 UTC:
- Google Play Production reported Express `com.express.usuario1`, version `1.6.4`, build `152`, status `completed`, available to all.
- Supabase `app_release_gate` recorded Production build 152 and next build 153, linked to the exact production-signed candidate and QA artifact hashes.
- The read-only sync recorded Play build 152 as matched and available to all.
- `android-build-worker` was deployed as version 50. The sync failure caused by Google Play omitting `versionName` was fixed in merged Express PR #333. PRs #331 and #332 established the Play read and initial sync trigger.
- The Admin release-management update was deployed through Admin PRs #135 and #136. The workflow and controls are documented in the Admin repository at `docs/GOOGLE_PLAY_PRODUCTION_AUTO_SYNC.md`.

Current behavior:
- The GitHub workflow reads the Google Play Production track every 15 minutes and sends an owner-authenticated observation to the worker. It reads through a temporary Play edit and deletes it without validating or committing.
- Admin refreshes its release status about every 3 minutes while open.
- Syncing a published build updates the verified Production baseline and next build counter. It does **not** activate an in-app notice, make an update critical, send a push, or upload/promote an app.
- Admin Distribution only accepts the exact verified signed build. Saving “Versión actual” publishes that build to the app's update-check RPC. The separate “Avisar actualización a usuarios” action is a user-facing notification flow; don't treat Play sync as having sent it.
- Saving “Actualización crítica” for build 152 sets the update as mandatory. Android clients with a build number below 152 are blocked when they receive the update record; build 152 is not blocked by itself. The app checks on launch and every 15 minutes. Do not enable this setting unless the owner explicitly asks.
- The next Production build number is 153 as of the verification above. Re-read live Admin/Play state before preparing it; do not rely on this number after another release.

## Passenger location notification issue

See `docs/PASSENGER_LOCATION_NOTIFICATION_DIAGNOSTIC_20261027.md` for the video review and code references.

Verified from the video and current source:
- The visible app screen is Passenger home (“¿A dónde vas?”).
- Android's “Express · ubicación activa” ongoing notification is triggered by the passenger map's GPS-follow stream, because Android `positionStream()` currently always adds a foreground-service notification.
- The notification text is generic and does not prove that the driver is online. The backend transition guard sets driver status offline when changing away from Driver, unless an active trip or delivery prevents the transition. Verify `driver_profiles.online_status` for a specific account if needed.
- A safe proposed fix is to use a foreground-only GPS stream without the ongoing driver-style notification for idle passenger map-follow, while retaining the foreground service for driver-online/background tracking and active services that need it.
- Code fix prepared on the working branch (not built, not deployed, not uploaded): `ExpressLocationService.positionStream(foregroundService: false)` is used only by the passenger idle map-follow in `lib/video_style_home.dart`. Driver tracking keeps the default foreground notification. Test coverage added in `test/location_service_test.dart`. Status is **unverified on device** until a new Android build is requested and tested.

## Address selection and descriptions

The address/pin flow was reported as failing to show reverse-geocoded descriptions and to reject a trip request after map-pin selection. Code changes were prepared for web and Android; the owner later reported “Nada sigue igual” before requesting build 152 with the change. There is no post-install confirmation in the available history. Treat this issue as **unverified**, not resolved; reproduce on the current web and build 152 before claiming success or changing the flow again.

## Safe handoff rules

- Do not infer current production state from this snapshot alone; confirm the live Play track and Admin state before another release.
- Do not upload, promote, or publish a new Android build unless the owner explicitly orders that step. Web/Admin publication does not authorize Play publication.
- Do not activate the critical update flag or send update notices on the owner's behalf without an explicit request.
- Keep Preview and Production data isolated by authenticated account as specified in `AGENTS.md`.
- Update this handoff after verified production releases or when one of the unresolved issues changes state. Preserve prior decisions as history; do not leave contradictory old status text presented as current.
