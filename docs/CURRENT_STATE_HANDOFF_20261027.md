# Current operational handoff — Express (updated 2026-10-29)

This is the current operational snapshot for the next engineer or AI. It replaces older progress messages and release counters as a status source. Owner-approved architecture and security rules in `AGENTS.md` remain in force. Older design proposals and “deploy still running” chat updates are historical; verify live state before acting.

## Android release and Play synchronization

Last verified on 2026-10-29 around 13:46 UTC:
- Google Play Production reported Express `com.express.usuario1`, version `1.6.4`, build `152`, status `completed`, available to all.
- Build `1.6.4+153` was built from source SHA `4a6f04f78c09bf6c8fa53abded37693cfef05337`, based on the exact build 152 source SHA `89f253c42e79942c1d1c6785c7a7297046f75cbe`.
- The signed APK and AAB were verified and uploaded to Google Play **Internal**. Supabase `build_jobs` marks the candidate `ready`; SHA-256 values and download URLs are recorded there. GitHub Actions run [40882798933](https://github.com/jorge2610g/Expressdelivery/actions/runs/40882798933) completed successfully.
- The release flow recorded **manual device QA pending**. No emulator or real-phone test is claimed. Do not promote build 153 to Production until the owner tests it and explicitly authorizes promotion.
- Supabase `app_release_gate` still records Production build 152; its next reserved build number is 154 after the Internal upload. No Production release was made.
- `android-build-worker` is deployed as version 51. It retains the current Google Play sync behavior and narrowly authorizes the owner-dispatched `build153-gps-repair` workflow for this 1.6.4+153 Internal candidate.
- The read-only sync and dashboard behavior below remain as described. PRs #331–#333 established and fixed the Play read/sync flow.
- The Admin release-management update was deployed through Admin PRs #135 and #136. The workflow and controls are documented in the Admin repository at `docs/GOOGLE_PLAY_PRODUCTION_AUTO_SYNC.md`.

Current behavior:
- The GitHub workflow reads the Google Play Production track every 15 minutes and sends an owner-authenticated observation to the worker. It reads through a temporary Play edit and deletes it without validating or committing.
- Admin refreshes its release status about every 3 minutes while open.
- Syncing a published build updates the verified Production baseline and next build counter. It does **not** activate an in-app notice, make an update critical, send a push, or upload/promote an app.
- Admin Distribution only accepts the exact verified signed build. Saving “Versión actual” publishes that build to the app's update-check RPC. The separate “Avisar actualización a usuarios” action is a user-facing notification flow; don't treat Play sync as having sent it.
- Saving “Actualización crítica” for build 152 sets the update as mandatory. Android clients with a build number below 152 are blocked when they receive the update record; build 152 is not blocked by itself. The app checks on launch and every 15 minutes. Do not enable this setting unless the owner explicitly asks.
- The next reserved Production build number is 154 after the Internal 153 upload. Re-read live Admin/Play state before preparing it; do not rely on this number after another release.

## Security alert repaired — Android Play sync table

- Migration `20261029201736_enable_android_play_sync_rls_20261029.sql` enables RLS on `public.android_play_production_sync`.
- The table remains server-only: `anon` and `authenticated` have no direct grants and no RLS policies are intentionally defined. The worker uses `service_role`; its `BYPASSRLS` capability and the existing `postgres`-owned `SECURITY DEFINER` RPCs preserve the intended server/admin flows.
- Post-migration SQL confirmed `anon`/`authenticated` still have no `SELECT`, `INSERT`, or `UPDATE` privilege, while `service_role` and `postgres` retain the required access. No `FORCE ROW LEVEL SECURITY` was set.

## Passenger location notification issue

See `docs/PASSENGER_LOCATION_NOTIFICATION_DIAGNOSTIC_20261027.md` for the video review and code references.

Status audited on 2026-10-29 15:14 UTC:
- Android build 153 configures the ongoing background-location notification for the driver location stream only; passenger map-follow does not request that notification.
- The driver updates its own marker locally before the network write. However, the passenger callback reads `message['payload']`; the reviewed Supabase Dart `onBroadcast` implementations pass the payload map directly. Normal broadcasts are therefore discarded before updating the passenger marker.
- The callback bug in web commit `76eba26ffbbda767fa441d4c412ebcc56ff65fe6` was corrected in `00c05d2fff20a6130a29ab7d1c65f192980e1e4b`. Pages run [40899895071](https://github.com/jorge2610g/Expressdelivery/actions/runs/40899895071) passed analysis, regression tests, builds and deployment. A real trip is still needed to confirm marker movement.
- The realtime migration source and exact build-153 worker allowlist are now included in `main`, matching the already-applied Supabase migration and deployed worker behavior.
- The driver-only notification change remains in build 153. Phone QA is still required for notification visibility, live marker movement, and reconnect behavior.

Historical diagnosis from the original video and source:
- The visible app screen is Passenger home (“¿A dónde vas?”).
- Android's “Express · ubicación activa” ongoing notification is triggered by the passenger map's GPS-follow stream, because Android `positionStream()` currently always adds a foreground-service notification.
- The notification text is generic and does not prove that the driver is online. The backend transition guard sets driver status offline when changing away from Driver, unless an active trip or delivery prevents the transition. Verify `driver_profiles.online_status` for a specific account if needed.
- A safe proposed fix is to use a foreground-only GPS stream without the ongoing driver-style notification for idle passenger map-follow, while retaining the foreground service for driver-online/background tracking and active services that need it.
- The diagnosis above records the original cause; the 153 change and its manual QA status supersede the former “no code fix” conclusion.

## Address selection and descriptions

The address/pin flow was reported as failing to show reverse-geocoded descriptions and to reject a trip request after map-pin selection. Code changes were prepared for web and Android; the owner later reported “Nada sigue igual” before requesting build 152 with the change. There is no post-install confirmation in the available history. Treat this issue as **unverified**, not resolved; reproduce on the current web and build 152 before claiming success or changing the flow again.

## Safe handoff rules

- Do not infer current production state from this snapshot alone; confirm the live Play track and Admin state before another release.
- Build 153 is uploaded to Internal for manual testing. Its passenger-map Realtime callback has a confirmed defect; do not promote it to Production. The corrected source needs a new candidate after the current phone QA and release identity are reconciled.
- Do not activate the critical update flag or send update notices on the owner's behalf without an explicit request.
- Keep Preview and Production data isolated by authenticated account as specified in `AGENTS.md`.
- Update this handoff after verified production releases or when one of the unresolved issues changes state. Preserve prior decisions as history; do not leave contradictory old status text presented as current.

## Remaining work

- Real-phone test of build 153 remains pending; the user should confirm the driver's own marker and driver-only notification. Build 153 is expected to discard incoming passenger-map Realtime broadcasts due to the callback bug above.
- Publish the corrected callback in Android as a new Internal candidate, then validate passenger marker movement and reconnect behavior. The web correction is deployed; live-trip QA remains pending.
- The address-by-pin issue remains unverified. Reproduce it on current web and build 153 before claiming it is fixed.
- Adminexpress PR #137 remains open as a draft. Module-specific operator permissions and delete behavior need review and verification.
- Treat older PR backlog and any other unverified reports as open until reviewed; this release did not close them.
