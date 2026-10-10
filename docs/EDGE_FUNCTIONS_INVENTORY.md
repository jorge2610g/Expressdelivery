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

## Comparación repo ↔ desplegado (2026-10-10)

| Función | Versión | Resultado | Acción |
|---|---|---|---|
| android-build-worker | v38 | **difería**: desplegado acepta `single-app-candidate-apk+aab` como candidato de Producción | repo alineado (copia exacta, diff byte a byte) |
| express-qa-monitor | v22 | **difería**: desplegado autoriza también `express-qa-collect-all.yml` | repo alineado |
| express-load-lab | v28 | **difería**: desplegado bloquea `scope=production` (PR #100 no fusionada) | repo alineado |
| express-push-dispatch | v37 | coincide (marcadores) | — |
| express-qa-provision | v22 | coincide (marcadores) | — |
| driver-subscription-payments | v25 | coincide (marcadores) | — |
| driver-subscription-admin | v19 | coincide (marcadores) | — |
| driver-subscription-webhook | v17 | coincide (marcadores) | — |
| zone-payment-admin | v16 | coincide (marcadores) | — |
| marketplace-payments | v18 | coincide (marcadores) | — |
| zego-call | v8 | coincide (marcadores) | — |

`android-build-worker` se comparó byte a byte. El resto se comparó por 5–9 fragmentos distintivos del código desplegado (la herramienta no permite volcar esas funciones a archivo); una diferencia menor fuera de esos fragmentos no quedaría detectada.

### Hallazgos en el código desplegado (no corregidos; requieren despliegue autorizado)

1. **driver-subscription-admin, zone-payment-admin, express-load-lab** autorizan solo con `is_admin()`. Una cuenta Admin Preview-only puede guardar/verificar credenciales reales de VeriPagos y Mercado Pago de Producción. Corrección propuesta: exigir además `admin_environment_allowed('production')` (load-lab: `'preview'`).
2. **marketplace-payments** `plus_verify`: cuando el pago ya está aprobado responde `{..., payment_id}` con una variable inexistente → `ReferenceError` → HTTP 500. Debe ser `payment_id: paymentId`.
3. **express-push-dispatch**: `packageName.isEmpty` (sintaxis Dart) es siempre `undefined` en TypeScript, así que una petición sin `package` no se acepta; y el secreto del webhook se compara con `!==` (no tiempo constante).

### Estado de las correcciones (2026-10-10)

| Hallazgo | Repo | QA | Producción |
|---|---|---|---|
| `zone-payment-admin` exige `admin_environment_allowed('production')` | ✅ | ✅ v1 | ✅ v17 |
| `driver-subscription-admin` exige `admin_environment_allowed('production')` | ✅ | ✅ v1 | ✅ v20 |
| `marketplace-payments` `payment_id: paymentId` | ✅ | ✅ v4 | ✅ v19 |
| `express-load-lab` exige `admin_environment_allowed('preview')` | ✅ | — | pendiente (CLI) |
| `express-push-dispatch` comparación en tiempo constante; se elimina `.isEmpty` sin cambiar comportamiento | ✅ | — | pendiente (CLI) |

- Mismo `ezbr_sha256` en QA y Producción para las tres desplegadas. Arranque verificado vía `pg_net` con clave anónima (`No autorizado` / `Sesión inválida`). La rama "admin sin Producción" no se probó extremo a extremo (sin JWT de usuario).
- `deno check` 2.1.4: versiones nuevas sin errores; originales con 3 errores (`payment_id`, `isEmpty`).
- Pendientes por CLI (byte a byte): `supabase functions deploy express-push-dispatch --no-verify-jwt` y `supabase functions deploy express-load-lab`.
- Rollback: re-desplegar `git show ec3ee7f:supabase/functions/<slug>/index.ts`.
