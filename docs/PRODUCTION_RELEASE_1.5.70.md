# Express Android 1.5.70 build 111

Production-signed validation release prepared on 2026-10-01.

## Included
- Express launcher icon (blue mark with white bolt).
- Android hardening: backups disabled and cleartext HTTP disabled.
- OAuth callback deep link for the production package `com.express.usuario`.
- Google OAuth client flow prepared behind `EXPRESS_GOOGLE_AUTH_ENABLED`.
- Existing passenger/driver flows remain unchanged.

## Security review
- Public application tables use RLS.
- Sensitive account and driver approval fields are protected with column-level update grants.
- Android signing stays in the protected build worker flow and is not committed to source.
- No production service-role or Google API secrets were found embedded in the client repository.
- Google OAuth remains disabled in the UI until the external Google provider credentials and Supabase redirect allow-list are configured.

This build is intended for production-signed validation and is not automatically published as a mandatory in-app release.
