# Trazabilidad de migraciones Production — corte 2026-10-24

Comparación de las 43 migraciones de Production desde el 2026-10-15 inclusive con los árboles actuales y el historial Git de `Expressdelivery` y `Adminexpress`. La lista de Production se consultó en Supabase en modo lectura. Se compara el slug SQL quitando, cuando aplica, el timestamp final agregado al nombre. Una coincidencia de slug no prueba que el contenido sea idéntico.

**Resultado:** 20 fuentes actuales coinciden también en versión, 10 tienen el mismo slug pero distinto timestamp entre el registro de Production y el archivo fuente actual, 0 solo aparecen en la historia Git, y 13 no tienen archivo de migración del mismo slug en el material revisado. No se reconstruye ni se vuelve a ejecutar ninguna migración a partir del nombre.

## Registro

| Versión Production | Nombre registrado | Estado de fuente | SQL localizado |
|---|---|---|---|
| 20261016051252 | `native_push_floating_offer_device_optin_20261016` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261017004342 | `offer_lifetime_v3` | FUENTE ACTUAL · versión coincide | Expressdelivery/supabase/migrations/20261017004342_offer_lifetime_v3.sql |
| 20261018050413 | `driver_zone_policy_toggle` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261018054441 | `user_call_preferences_routing` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261018063728 | `call_presence_routing` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261018160847 | `backup_native_push_tokens_pre_overlay_20261018` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261018160905 | `push_token_overlay_state_20261018` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261018160950 | `push_token_overlay_state_anon_execute_guard_20261018` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261019123654 | `android_play_update_distribution_20261019` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261019150113 | `production_only_android_update_141_20261019` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261020071326 | `operator_role_zone_filter` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020071326_operator_role_zone_filter.sql |
| 20261020121418 | `zone_scope_read_guard_phase1` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020121418_zone_scope_read_guard_phase1.sql |
| 20261020133005 | `operator_zone_scope_phase2` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020133005_operator_zone_scope_phase2.sql |
| 20261020175406 | `operator_module_capabilities` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020175406_operator_module_capabilities.sql |
| 20261020175411 | `operator_zone_push` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020175411_operator_zone_push.sql |
| 20261020175416 | `operator_zone_fares` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020175416_operator_zone_fares.sql |
| 20261020175421 | `operator_zone_payments` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020175421_operator_zone_payments.sql |
| 20261020175425 | `operator_zone_subscriptions` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020175425_operator_zone_subscriptions.sql |
| 20261020175429 | `operator_zone_activate_verified` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261020175429_operator_zone_activate_verified.sql |
| 20261021010453 | `operator_capability_guard_hardening` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261021010453_operator_capability_guard_hardening.sql |
| 20261021011624 | `operator_module_guard_restore_central_reads` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261021011624_operator_module_guard_restore_central_reads.sql |
| 20261021024515 | `admin_operator_banner_module_guard_20261021` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261021025214 | `driver_vehicle_category_dispatch_and_atomic_save` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261022200756 | `zone_cancellation_fees` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261022120000_zone_cancellation_fees.sql |
| 20261022221110 | `fix_cancellation_fee_zone_lookup` | FUENTE ACTUAL · versión coincide | Expressdelivery/supabase/migrations/20261022221110_fix_cancellation_fee_zone_lookup.sql |
| 20261022222451 | `explain_cancellation_debt_block` | FUENTE ACTUAL · versión coincide | Expressdelivery/supabase/migrations/20261022222451_explain_cancellation_debt_block.sql |
| 20261022223539 | `passenger_cancellation_fee_after_acceptance` | FUENTE ACTUAL · versión coincide | Expressdelivery/supabase/migrations/20261022223539_passenger_cancellation_fee_after_acceptance.sql |
| 20261023030955 | `zone_service_commission_settlement_20261023101500` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261023101500_zone_service_commission_settlement.sql |
| 20261023050132 | `driver_web_onboarding_manual_zone_20261023131500` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261023131500_driver_web_onboarding_manual_zone.sql |
| 20261023071944 | `fix_passenger_cancellation_debt_guard_zone` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261023170000_fix_passenger_cancellation_debt_guard_zone.sql |
| 20261023140659 | `fix_cancellation_debt_gateway_role` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261023170100_fix_cancellation_debt_gateway_role.sql |
| 20261023144100 | `verified_cancellation_debt_payment_recovery` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261023153100 | `fix_verified_debt_checkout_role` | SIN FUENTE DEL MISMO SLUG | No localizada en la historia revisada de ambos repos |
| 20261023173108 | `admin_zonal_debt_management_20261023` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261023173108_admin_zonal_debt_management_20261023.sql |
| 20261023183207 | `admin_finance_allow_debit_wallet` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261023183207_admin_finance_allow_debit_wallet.sql |
| 20261023183433 | `admin_finance_target_email` | FUENTE ACTUAL · versión coincide | Adminexpress/supabase/migrations/20261023183433_admin_finance_target_email.sql |
| 20261023195625 | `admin_adjustment_wallet_debt` | FUENTE ACTUAL · versión distinta | Adminexpress/supabase/migrations/20261023192317_admin_adjustment_wallet_debt.sql |
| 20261023195630 | `enforce_admin_adjustment_debt` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261023192321_enforce_admin_adjustment_debt.sql |
| 20261023200058 | `backfill_unsettled_admin_adjustment_debts` | FUENTE ACTUAL · versión distinta | Adminexpress/supabase/migrations/20261023195930_backfill_unsettled_admin_adjustment_debts.sql |
| 20261023213423 | `enable_rls_finance_provider_settings` | FUENTE ACTUAL · versión coincide | Expressdelivery/supabase/migrations/20261023213423_enable_rls_finance_provider_settings.sql |
| 20261023213509 | `add_service_role_policies_finance_settings` | FUENTE ACTUAL · versión coincide | Expressdelivery/supabase/migrations/20261023213509_add_service_role_policies_finance_settings.sql |
| 20261023222947 | `wallet_debt_threshold_settings` | FUENTE ACTUAL · versión distinta | Adminexpress/supabase/migrations/20261023221937_wallet_debt_threshold_settings.sql |
| 20261023223149 | `enforce_wallet_debt_thresholds` | FUENTE ACTUAL · versión distinta | Expressdelivery/supabase/migrations/20261023221938_enforce_wallet_debt_thresholds.sql |

## Pendientes de reconciliación

Para los 10 casos con timestamp distinto, validar si el contenido del archivo es exactamente el que se aplicó: el registro de migraciones solo aporta versión/nombre. Para los 13 sin archivo de migración del mismo slug, encontrar el SQL original o demostrar un reemplazo comparando los objetos y definiciones del esquema actual. La lista de nombres por sí sola no prueba que esos cambios falten en Production. No editar el historial de Production ni reaplicar versiones ya registradas.

## Evidencia adicional de solo lectura

- El repositorio conserva `docs/pending_migrations/20261018_push_token_overlay_state_PROPOSAL.sql`, que se declara explícitamente propuesta no aplicada. Production sí registra `20261018160905 push_token_overlay_state_20261018`, y actualmente existe `set_push_token_overlay_state(text, boolean)`. El archivo es una pista de diseño, no una fuente probada del SQL desplegado.
- El esquema actual contiene `native_push_tokens` y `user_call_preferences`; existen RPCs `register_native_push_token_v2`, `set_push_token_overlay_state`, `set_my_call_preferences`, `admin_driver_zone_policy_get/set`, `admin_android_update_distributions`, `admin_save_android_update_distribution` y dos versiones de `service_finalize_verified_cancellation_debt_gateway`. Que existan no identifica la migración que los creó ni confirma que el SQL local coincida.
- Production se consultó en solo lectura para el registro de migraciones y nombres/tipos de esos objetos; no se leyeron filas de clientes ni se modificó el esquema.
- Para fuentes con timestamp distinto también se verificó la presencia de objetos ancla: las tablas de deuda por cancelación, `settle_wallet_payment`, `submit_driver_web_onboarding`, el guard de solicitudes, los gateways de deuda v1/v2 y `wallet_debt_limit_status_v1`. Es evidencia de que la función existe hoy, no de que el SQL aplicado sea byte por byte el archivo local.
- Revisión adicional de privilegios: los RPCs v2 de settlement de deuda son ejecutables por `service_role` y no por `anon`/`authenticated`; `set_push_token_overlay_state` no es ejecutable por `anon`. Entre los demás RPCs revisados que permiten `anon`, el cuerpo comprueba identidad/cuenta activa o rol admin; `driver_zone_policy_enabled` solo expone un booleano. No se encontró un bypass de identidad en los RPCs comprobados.

## Cruce funcional de los 13 sin archivo de migración

Estas observaciones prueban que hay superficie relacionada en el esquema actual; **no** prueban que el archivo de un repo sea idéntico al SQL aplicado. Las consultas solo inspeccionaron nombres, columnas, definiciones de acceso y privilegios.

| Migración Production | Superficie relacionada observada en el esquema actual | Resultado del cruce |
|---|---|---|
| `native_push_floating_offer_device_optin_20261016` | `native_push_tokens.floating_offer_enabled`, `permission_checked_at` y uso en `express-push-dispatch` | El flujo existe; falta el SQL histórico exacto. |
| `driver_zone_policy_toggle` | `admin_driver_zone_policy_get/set`, `driver_zone_policy_enabled` | RPCs presentes; las administrativas comprueban `is_admin`. |
| `user_call_preferences_routing` | Tabla `user_call_preferences`, RPC `set_my_call_preferences` y `call_route_for_counterpart` | Ruta de preferencias/llamada presente; el setter exige identidad y cuenta activa. |
| `call_presence_routing` | Tabla `private_voice_calls`, RPC `set_my_presence` | Presencia actual presente; el RPC exige identidad y cuenta activa. |
| `backup_native_push_tokens_pre_overlay_20261018` | No se encontró una tabla persistente de respaldo con ese nombre | Puede haber sido una copia temporal de datos; no se puede probar su efecto solo con el esquema actual. |
| `push_token_overlay_state_20261018` | Columnas de estado en `native_push_tokens`, RPC homónimo; hay propuesta SQL en `docs/pending_migrations/` | Estado desplegado presente; la propuesta no demuestra el SQL que se aplicó. |
| `push_token_overlay_state_anon_execute_guard_20261018` | RPC presente y `anon` no tiene `EXECUTE` | El resultado de ACL esperado está activo; falta su migración fuente exacta. |
| `android_play_update_distribution_20261019` | Tabla `app_update_distributions` y RPCs de administración en Adminexpress | Distribución de versiones presente; falta reconciliar el SQL fuente. |
| `production_only_android_update_141_20261019` | `app_update_distributions` tiene columna `channel`; el cliente Admin integra la distribución | El esquema permite separar canales; no se comprobó el cuerpo/versionado exacto de esa migración. |
| `admin_operator_banner_module_guard_20261021` | RPCs `admin_operator_assert_module/record` y RPCs por módulo | Guards de operador presentes; falta demostrar qué parte añadió esa migración concreta. |
| `driver_vehicle_category_dispatch_and_atomic_save` | `driver_vehicles`, `save_driver_vehicle`, `update_my_driver_vehicle_services_for_review`, `driver_vehicle_supports_ride` | Flujo de vehículos presente; el SQL exacto de despacho/atomicidad no está en los repos. |
| `verified_cancellation_debt_payment_recovery` | `service_finalize_verified_cancellation_debt_gateway_v2` | RPC v2 presente; falta fuente de creación y comparación del cuerpo. |
| `fix_verified_debt_checkout_role` | El RPC v2 solo permite `service_role` (no `anon` ni `authenticated`) | ACL de servicio activo; la procedencia exacta sigue abierta. |

Este cruce reduce el riesgo de confundir “sin archivo fuente” con “función ausente”: se localizaron superficies relacionadas para 12 de 13 registros. El registro de respaldo es el único que no dejó un objeto persistente identificable. No se reconstruye el histórico ni se propone reejecutar nada.

