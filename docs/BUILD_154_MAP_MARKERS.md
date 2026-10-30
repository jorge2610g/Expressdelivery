# Candidate 154 — vehicle markers and live heading

Owner-approved 2026-10-30. Shared passenger/driver Web and official Android code.

- Auto, Moto and Motocar use transparent top-down illustrations with a white outline.
- Each nearby marker uses its own server-returned vehicle type. While idle the map can show the mixed nearby fleet; once a route is confirmed or a request exists, the configured service filter is preserved.
- Driver uses the active registered vehicle, not a city or generic car default. Unknown vehicle information renders a neutral location marker.
- In-progress trips show a blue navigation arrow on both driver and passenger maps; service tracking reuses the same component. Active delivery stages also use the arrow on the driver map.
- Heading uses valid reported GPS course, with movement bearing as fallback, a 4 m drift threshold, last-heading retention while stopped, and shortest-turn animation across north. This is heading visualization, not turn-by-turn navigation.
- GPS stays local and immediate before awaiting backend writes. Passenger idle GPS does not request the driver's Android ongoing-location notification. Background location remains enabled for the primary driver runtime.
- The previously corrected direct Realtime payload callback is retained. The owner verified live Web tracking before these marker changes; post-change Web/device validation is still needed.

## Motocar rollout

The artwork and presentation aliases are ready. The live vehicle constraint still only permits car, motorcycle and XL. The owner confirmed Motocar is cargo/parcels only, never passenger transport. The owner chose a dedicated Motocar tariff and will provide its values later. Commercial enablement remains pending those values and driver-registration/dispatch validation. This candidate does not create fake vehicles, modify existing vehicle records or enable a new tariff.

## Release

Target: official package, version 1.6.4+154, signed APK+AAB, Google Play Internal only. Production promotion and critical update notices are separate actions. Check current release gate immediately before enqueueing. Web 154 was deployed successfully on 2026-10-30 (Pages run 40985688956, source 384bfad6578e3eb49703f08753035c509c6efc6d); version.json and all three marker PNGs were checked on the official domain. Android candidate source c337e26a238dc195757d99fafa763b71fcd8ea4d is building in run 40985734671. Device QA remains pending until the owner tests the candidate.
