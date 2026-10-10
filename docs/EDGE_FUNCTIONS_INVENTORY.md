# Inventario de Edge Functions (Producción `zgpijrznvaskgcmauwxx`) · 2026-10-10

Código fuente versionado en `supabase/functions/<slug>/index.ts`. Copias exactas de lo desplegado (descargadas el 2026-10-10).

| Slug | verify_jwt | Estado | Nota |
|---|---|---|---|
| android-build-worker | false | activa | auth propia (OIDC GitHub) |
| express-push-dispatch | false | activa | secreto `x-express-push-secret` |
| express-qa-monitor | false | activa | auth propia (OIDC GitHub) |
| express-qa-provision | false | activa | auth propia (OIDC GitHub) |
| express-load-lab | true | activa | |
| driver-subscription-payments | true | activa | |
| driver-subscription-admin | true | activa | |
| driver-subscription-webhook | false | activa | Basic Auth VeriPagos |
| zone-payment-admin | true | activa | |
| marketplace-payments | true | activa | |
| zego-call | true | activa | llamadas privadas |
| didit-identity | true | **retirada** (410) | Didit desactivado por decisión de negocio |
| didit-identity-prod | true | **retirada** (410) | idem |
| didit-webhook | false | **retirada** (204 sin procesar) | idem |
| didit-webhook-prod | false | **retirada** (204 sin procesar) | idem |
| phone-otp | true | **retirada** (410) | OTP/SMS desactivado |
| unimatrix-health-check | true | **retirada** (410) | |
| zego-health-check | true | **retirada** (410) | |

Las funciones retiradas se mantienen desplegadas para que APK antiguos reciban una respuesta controlada. **No reactivar Didit ni SMS sin autorización.** Al desplegar, respetar el `verify_jwt` de esta tabla.
