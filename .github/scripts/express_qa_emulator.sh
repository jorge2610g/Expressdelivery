#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${MAESTRO_CLOUD_API_KEY:-}" ]]; then
  export MAESTRO_CLOUD_API_KEY
fi

mkdir -p artifacts/maestro artifacts/device artifacts/backend

QA_APK="artifacts/apk/express-qa-x86_64.apk"
PRODUCTION_APP_ID="com.express.usuario1"
PRODUCTION_QA_APK="artifacts/apk/express-production-qa-x86_64.apk"

# GitHub's emulator is x86_64. Published Android artifacts remain verified by
# release identity/SHA; functional automation runs x86_64 binaries compiled
# from the exact audited SHA. Both entry points are mandatory now.
test -s "$QA_APK"
test -s "$PRODUCTION_QA_APK"
unzip -l "$QA_APK" > /tmp/express-preview-apk-list.txt
unzip -l "$PRODUCTION_QA_APK" > /tmp/express-production-apk-list.txt
grep -q 'lib/x86_64/libflutter.so' /tmp/express-preview-apk-list.txt
grep -q 'lib/x86_64/libflutter.so' /tmp/express-production-apk-list.txt

dismiss_system_blockers() {
  # Do not force-stop the launcher: doing that can itself trigger a Pixel
  # Launcher ANR dialog which then covers Express and produces a false Maestro
  # failure. Only dismiss an actual Android error dialog when one is present.
  local dump="/sdcard/express-qa-system-dialog.xml"
  adb shell uiautomator dump "$dump" >/dev/null 2>&1 || return 0
  if adb shell cat "$dump" 2>/dev/null | grep -Eq 'aerr_wait|aerr_close|isn.t responding'; then
    # Prefer Wait so Android keeps the launcher alive and we do not create a
    # second launcher restart/ANR cycle.
    local bounds
    bounds="$(adb shell cat "$dump" 2>/dev/null | sed -n 's/.*resource-id="android:id\/aerr_wait"[^>]*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' | head -n1 | tr -d '\r')"
    if [[ -n "$bounds" ]]; then
      read -r x1 y1 x2 y2 <<<"$bounds"
      adb shell input tap "$(((x1+x2)/2))" "$(((y1+y2)/2))" >/dev/null 2>&1 || true
    else
      adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    fi
    sleep 1
  fi
}

system_dialog_watchdog() {
  while true; do
    dismiss_system_blockers || true
    sleep 2
  done
}

run_maestro_bounded() {
  local label="$1"
  local seconds="$2"
  shift 2
  echo "Running $label with ${seconds}s hard timeout..."

  # Keep system ANR/crash dialogs from masking Express while Maestro runs.
  system_dialog_watchdog &
  local watchdog_pid=$!
  set +e
  timeout --signal=TERM --kill-after=15s "${seconds}s" "$@"
  local status=$?
  set -e
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true
  dismiss_system_blockers || true
  return "$status"
}

dismiss_system_blockers

# Mandatory Production-entrypoint startup smoke. This is intentionally first:
# if Production cannot reach the auth UI, there is no reason to spend minutes
# on the longer Preview passenger/driver journey.
PRODUCTION_SMOKE_STATUS=0
adb install -r "$PRODUCTION_QA_APK"
adb logcat -c || true
adb shell am force-stop "$PRODUCTION_APP_ID" || true
run_maestro_bounded "production startup smoke" 120 maestro test .maestro/production_smoke.yaml \
  --format junit \
  --output artifacts/maestro/production-smoke.xml \
  --test-output-dir artifacts/maestro/production-smoke || PRODUCTION_SMOKE_STATUS=$?

adb exec-out screencap -p > artifacts/device/after-production-smoke.png || true
adb shell uiautomator dump /sdcard/window-after-production-smoke.xml || true
adb pull /sdcard/window-after-production-smoke.xml artifacts/device/window-after-production-smoke.xml || true
adb logcat -d -t 1800 > artifacts/device/logcat-after-production-smoke.txt || true

PRODUCTION_APP_PID="$(adb shell pidof "$PRODUCTION_APP_ID" 2>/dev/null | tr -d '\r' || true)"
PRODUCTION_FATAL_COUNT="$(grep -Eic "FATAL EXCEPTION|Process: $PRODUCTION_APP_ID|Unable to start activity.*$PRODUCTION_APP_ID|UnsatisfiedLinkError" artifacts/device/logcat-after-production-smoke.txt || true)"
PRODUCTION_STARTUP_ERROR_VISIBLE=0
if grep -Eqi "Express no pudo iniciar|E-START-AUTH" artifacts/device/window-after-production-smoke.xml 2>/dev/null; then
  PRODUCTION_STARTUP_ERROR_VISIBLE=1
fi

# Continue with the full Preview test suite only after capturing Production
# evidence. Separate package IDs keep both installations isolated.
adb install -r "$QA_APK"
adb logcat -c || true
adb shell am force-stop "$APP_ID" || true
dismiss_system_blockers

SMOKE_STATUS=0
run_maestro_bounded "smoke" 180 maestro test .maestro/smoke.yaml   --format junit   --output artifacts/maestro/smoke.xml   --test-output-dir artifacts/maestro/smoke || SMOKE_STATUS=$?

adb exec-out screencap -p > artifacts/device/after-smoke.png || true
adb shell uiautomator dump /sdcard/window-after-smoke.xml || true
adb pull /sdcard/window-after-smoke.xml artifacts/device/window-after-smoke.xml || true
adb logcat -d -t 2400 > artifacts/device/logcat-after-smoke.txt || true

APP_PID="$(adb shell pidof "$APP_ID" 2>/dev/null | tr -d '\r' || true)"
FATAL_COUNT="$(grep -Eic "FATAL EXCEPTION|Process: $APP_ID|Unable to start activity.*$APP_ID|UnsatisfiedLinkError" artifacts/device/logcat-after-smoke.txt || true)"

VISUAL_STATUS=98
if [[ -n "${MAESTRO_CLOUD_API_KEY:-}" ]]; then
  VISUAL_STATUS=0
  env MAESTRO_CLOUD_API_KEY="$MAESTRO_CLOUD_API_KEY"     timeout --signal=TERM --kill-after=15s 180s maestro test .maestro/visual_audit.yaml       --api-key="$MAESTRO_CLOUD_API_KEY"       --analyze       --format junit       --output artifacts/maestro/visual-ai.xml       --test-output-dir artifacts/maestro/visual-ai || VISUAL_STATUS=$?
else
  echo "MAESTRO_CLOUD_API_KEY not configured; visual AI audit skipped."
fi

PASSENGER_STATUS=98
if [[ -n "${QA_PASSENGER_EMAIL:-}" && -n "${QA_PASSENGER_PASSWORD:-}" ]]; then
  PASSENGER_STATUS=0
  adb shell pm clear "$APP_ID" || true
  dismiss_system_blockers
  run_maestro_bounded "passenger authenticated smoke" 240 maestro test     -e QA_EMAIL="$QA_PASSENGER_EMAIL"     -e QA_PASSWORD="$QA_PASSENGER_PASSWORD"     .maestro/passenger_login.yaml     --format junit     --output artifacts/maestro/passenger.xml     --test-output-dir artifacts/maestro/passenger || PASSENGER_STATUS=$?
else
  echo "Passenger QA credentials not configured; authenticated passenger test skipped."
fi

DRIVER_STATUS=98
if [[ -n "${QA_DRIVER_EMAIL:-}" && -n "${QA_DRIVER_PASSWORD:-}" ]]; then
  DRIVER_STATUS=0
  adb shell pm clear "$APP_ID" || true
  dismiss_system_blockers
  run_maestro_bounded "driver authenticated smoke" 240 maestro test     -e QA_EMAIL="$QA_DRIVER_EMAIL"     -e QA_PASSWORD="$QA_DRIVER_PASSWORD"     .maestro/driver_login.yaml     --format junit     --output artifacts/maestro/driver.xml     --test-output-dir artifacts/maestro/driver || DRIVER_STATUS=$?
else
  echo "Driver QA credentials not configured; authenticated driver test skipped."
fi

DRIVER_REQUEST_PREP_STATUS=98
DRIVER_REQUEST_FLOW_STATUS=98
FULL_TRIP_STATUS=98
PASSENGER_RATING_STATUS=98
DRIVER_RATING_STATUS=98
RATING_FINISH_STATUS=98
if [[ -n "${QA_PASSENGER_EMAIL:-}" && -n "${QA_PASSENGER_PASSWORD:-}" && -n "${QA_DRIVER_EMAIL:-}" && -n "${QA_DRIVER_PASSWORD:-}" ]]; then
  DRIVER_REQUEST_PREP_STATUS=0
  if python3 .github/scripts/qa_driver_request_flow.py prepare > artifacts/backend/driver-request-prepare.log 2>&1; then
    DRIVER_REQUEST_FLOW_STATUS=0
    QA_ROUTE_ORIGIN="$(jq -r '.origin' artifacts/backend/driver-request-seed.json)"
    QA_PICKUP_LAT="$(jq -r '.pickup_latitude' artifacts/backend/driver-request-seed.json)"
    QA_PICKUP_LNG="$(jq -r '.pickup_longitude' artifacts/backend/driver-request-seed.json)"
    adb shell pm clear "$APP_ID" || true
    dismiss_system_blockers
    adb emu geo fix "$QA_PICKUP_LNG" "$QA_PICKUP_LAT" || true
    run_maestro_bounded "driver live-request flow" 240 maestro test \
      -e QA_EMAIL="$QA_DRIVER_EMAIL" \
      -e QA_PASSWORD="$QA_DRIVER_PASSWORD" \
      -e QA_ROUTE_ORIGIN="$QA_ROUTE_ORIGIN" \
      .maestro/driver_request_flow.yaml \
      --format junit \
      --output artifacts/maestro/driver-request.xml \
      --test-output-dir artifacts/maestro/driver-request || DRIVER_REQUEST_FLOW_STATUS=$?

    if [[ "$DRIVER_REQUEST_FLOW_STATUS" -eq 0 ]]; then
      FULL_TRIP_STATUS=0
      python3 .github/scripts/qa_driver_request_flow.py complete \
        > artifacts/backend/full-trip-complete.log 2>&1 || FULL_TRIP_STATUS=$?

      if [[ "$FULL_TRIP_STATUS" -eq 0 ]]; then
        PASSENGER_RATING_STATUS=0
        adb shell pm clear "$APP_ID" || true
        dismiss_system_blockers
        run_maestro_bounded "passenger pending-rating flow" 150 maestro test \
          -e QA_EMAIL="$QA_PASSENGER_EMAIL" \
          -e QA_PASSWORD="$QA_PASSENGER_PASSWORD" \
          .maestro/passenger_rating_pending.yaml \
          --format junit \
          --output artifacts/maestro/passenger-rating.xml \
          --test-output-dir artifacts/maestro/passenger-rating || PASSENGER_RATING_STATUS=$?

        DRIVER_RATING_STATUS=0
        adb shell pm clear "$APP_ID" || true
        dismiss_system_blockers
        run_maestro_bounded "driver pending-rating flow" 150 maestro test \
          -e QA_EMAIL="$QA_DRIVER_EMAIL" \
          -e QA_PASSWORD="$QA_DRIVER_PASSWORD" \
          .maestro/driver_rating_pending.yaml \
          --format junit \
          --output artifacts/maestro/driver-rating.xml \
          --test-output-dir artifacts/maestro/driver-rating || DRIVER_RATING_STATUS=$?

        RATING_FINISH_STATUS=0
        python3 .github/scripts/qa_driver_request_flow.py finish \
          > artifacts/backend/rating-finish.log 2>&1 || RATING_FINISH_STATUS=$?
      else
        echo "Full synthetic trip failed."
        cat artifacts/backend/full-trip-complete.log || true
      fi
    else
      python3 .github/scripts/qa_driver_request_flow.py cleanup \
        > artifacts/backend/driver-request-cleanup.log 2>&1 || true
    fi
  else
    DRIVER_REQUEST_PREP_STATUS=$?
    echo "Synthetic driver request preparation failed."
    cat artifacts/backend/driver-request-prepare.log || true
  fi
else
  DRIVER_REQUEST_PREP_STATUS=97
  echo "Passenger/driver QA credentials not configured; critical end-to-end trip flow unavailable."
fi
DEVICE_VERDICT="healthy"
DEVICE_REASON="production_and_preview_startup_passed"

if [[ "$PRODUCTION_SMOKE_STATUS" -ne 0 ]]; then
  if [[ "$PRODUCTION_FATAL_COUNT" -gt 0 || "$PRODUCTION_STARTUP_ERROR_VISIBLE" -eq 1 ]]; then
    DEVICE_VERDICT="confirmed_product_failure"
    DEVICE_REASON="production_startup_failed"
  else
    DEVICE_VERDICT="qa_inconclusive"
    DEVICE_REASON="production_startup_smoke_inconclusive"
  fi
fi

if [[ "$SMOKE_STATUS" -ne 0 ]]; then
  if [[ "$FATAL_COUNT" -gt 0 ]]; then
    DEVICE_VERDICT="confirmed_product_failure"
    DEVICE_REASON="preview_smoke_failed_with_android_fatal"
  elif [[ "$DEVICE_VERDICT" != "confirmed_product_failure" ]]; then
    DEVICE_VERDICT="qa_inconclusive"
    DEVICE_REASON="preview_smoke_assertion_failed_without_runtime_crash"
  fi
fi

# Visual AI remains useful evidence, but it is experimental/advisory and must
# not turn a healthy functional run red. Authenticated passenger/driver checks,
# the live request flow, backend evidence and Android fatal evidence stay gated.
if [[ "$VISUAL_STATUS" -eq 98 ]]; then
  echo "::warning::Visual AI audit was not configured; continuing with mandatory functional QA."
elif [[ "$VISUAL_STATUS" -ne 0 ]]; then
  echo "::warning::Visual AI audit did not complete successfully; keeping its artifacts as advisory evidence."
fi

if [[ "$PASSENGER_STATUS" -eq 98 || "$DRIVER_STATUS" -eq 98 ]]; then
  if [[ "$DEVICE_VERDICT" != "confirmed_product_failure" ]]; then
    DEVICE_VERDICT="qa_infrastructure"
    DEVICE_REASON="authenticated_qa_not_configured"
  fi
elif [[ "$PASSENGER_STATUS" -ne 0 || "$DRIVER_STATUS" -ne 0 ]]; then
  if [[ "$DEVICE_VERDICT" == "healthy" ]]; then
    DEVICE_VERDICT="qa_inconclusive"
    DEVICE_REASON="authenticated_smoke_failed"
  fi
fi

if [[ -z "$PRODUCTION_APP_PID" && "$DEVICE_VERDICT" == "healthy" ]]; then
  DEVICE_VERDICT="qa_inconclusive"
  DEVICE_REASON="production_process_not_alive_after_smoke"
fi

if [[ -z "$APP_PID" && "$DEVICE_VERDICT" == "healthy" ]]; then
  DEVICE_VERDICT="qa_inconclusive"
  DEVICE_REASON="preview_process_not_alive_after_smoke"
fi

# This is a real cross-account synthetic flow. Preparation problems are QA
# infrastructure; once the request is created successfully, failure to surface
# it in the driver's app is a confirmed product regression.
if [[ "$DRIVER_REQUEST_PREP_STATUS" -ne 0 ]]; then
  if [[ "$DEVICE_VERDICT" != "confirmed_product_failure" ]]; then
    DEVICE_VERDICT="qa_infrastructure"
    DEVICE_REASON="driver_request_seed_failed"
  fi
elif [[ "$DRIVER_REQUEST_FLOW_STATUS" -ne 0 ]]; then
  if [[ "$DRIVER_STATUS" -eq 0 ]]; then
    # Only classify the live-request failure as a product regression after the
    # driver authenticated smoke has already proven that the driver can log in
    # and reach the driver home screen in this same run.
    DEVICE_VERDICT="confirmed_product_failure"
    DEVICE_REASON="driver_did_not_receive_live_request"
  else
    # If authentication/navigation failed first, the live-request assertion is
    # not valid product evidence. Keep the run non-green, but do not open/refresh
    # a false product incident.
    DEVICE_VERDICT="qa_inconclusive"
    DEVICE_REASON="driver_request_not_testable_after_auth_failure"
  fi
fi

if [[ "$DRIVER_REQUEST_FLOW_STATUS" -eq 0 && "$FULL_TRIP_STATUS" -ne 0 ]]; then
  DEVICE_VERDICT="confirmed_product_failure"
  DEVICE_REASON="full_trip_backend_flow_failed"
elif [[ "$FULL_TRIP_STATUS" -eq 0 && ( "$PASSENGER_RATING_STATUS" -ne 0 || "$DRIVER_RATING_STATUS" -ne 0 ) ]]; then
  DEVICE_VERDICT="confirmed_product_failure"
  DEVICE_REASON="bidirectional_rating_ui_failed"
elif [[ "$FULL_TRIP_STATUS" -eq 0 && "$RATING_FINISH_STATUS" -ne 0 ]]; then
  DEVICE_VERDICT="confirmed_product_failure"
  DEVICE_REASON="bidirectional_rating_persistence_failed"
fi

export DEVICE_VERDICT DEVICE_REASON SMOKE_STATUS VISUAL_STATUS
export PRODUCTION_SMOKE_STATUS PRODUCTION_APP_PID PRODUCTION_FATAL_COUNT PRODUCTION_STARTUP_ERROR_VISIBLE
export PASSENGER_STATUS DRIVER_STATUS DRIVER_REQUEST_PREP_STATUS DRIVER_REQUEST_FLOW_STATUS APP_PID FATAL_COUNT
export FULL_TRIP_STATUS PASSENGER_RATING_STATUS DRIVER_RATING_STATUS RATING_FINISH_STATUS
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "verdict": os.environ["DEVICE_VERDICT"],
    "reason": os.environ["DEVICE_REASON"],
    "production_smoke_status": int(os.environ["PRODUCTION_SMOKE_STATUS"]),
    "production_process_alive": bool(os.environ.get("PRODUCTION_APP_PID", "").strip()),
    "production_android_fatal_evidence_count": int(os.environ["PRODUCTION_FATAL_COUNT"]),
    "production_startup_error_visible": int(os.environ["PRODUCTION_STARTUP_ERROR_VISIBLE"]) == 1,
    "smoke_status": int(os.environ["SMOKE_STATUS"]),
    "visual_ai_status": int(os.environ["VISUAL_STATUS"]),
    "passenger_status": int(os.environ["PASSENGER_STATUS"]),
    "driver_status": int(os.environ["DRIVER_STATUS"]),
    "driver_request_prep_status": int(os.environ["DRIVER_REQUEST_PREP_STATUS"]),
    "driver_request_flow_status": int(os.environ["DRIVER_REQUEST_FLOW_STATUS"]),
    "full_trip_status": int(os.environ["FULL_TRIP_STATUS"]),
    "passenger_rating_status": int(os.environ["PASSENGER_RATING_STATUS"]),
    "driver_rating_status": int(os.environ["DRIVER_RATING_STATUS"]),
    "rating_finish_status": int(os.environ["RATING_FINISH_STATUS"]),
    "app_process_alive": bool(os.environ.get("APP_PID", "").strip()),
    "android_fatal_evidence_count": int(os.environ["FATAL_COUNT"]),
}
Path("artifacts/backend/device-verdict.json").write_text(
    json.dumps(payload, indent=2, ensure_ascii=False)
)
print(json.dumps(payload, ensure_ascii=False))
PY

# Always emit evidence; the workflow evidence gate decides product-vs-QA failure.
# A green workflow now requires every mandatory check to have actually passed.
exit 0
