# Exclusive zone coverage authority

`public.service_zones.coverage_mode` has two values: `radius` or `polygon`. The migration initializes the mode to the previous effective coverage (active polygon preferred, otherwise radius). `service_zone_id_for_point` does NOT fall back to the other method.

`admin_zone_coverage_save` combines zone creation/update, coverage selection, and deactivation/reuse of polygons atomically. Backend validates role, Admin environment allowance, coordinates, radius > 0 for radio, 3–300 valid distinct polygon vertices for polygon.

When mode=radius: center and radius are operative; zero active polygons for that zone. When mode=polygon: exactly one active polygon; radius remains stored for compatibility but is never used. Both Preview and Production Admin mutate this shared business configuration, but QA driver/trip/payment records remain isolated.

This migration is additive and does not delete existing active zones or polygon records. Existing stored modes were verified: Trinidad polygon / Iquique radius.
