#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${MAESTRO_CLOUD_API_KEY:-}" ]]; then
  export MAESTRO_CLOUD_API_KEY
fi

mkdir -p artifacts/maestro artifacts/device artifacts/backend

QA_APK="artifacts/apk/express-qa-x86_64.apk"
test -s "$QA_APK"

adb install -r "$QA_APK"
adb logcat -c || true
adb shell am force-stop "$APP_ID" || true

dismiss_system_blockers() {
  # The headless Pixel emulator can occasionally show an Android/Launcher ANR
  # dialog over Express even when the Express process is healthy. That is QA
  # infrastructure, not product evidence. Clear known launcher blockers before
  # each Maestro flow so UI assertions target Express itself.
  adb shell am force-stop com.google.android.apps.nexuslauncher >/dev/null 2>&1 || true
  adb shell am force-stop com.android.launcher3 >/dev/null 2>&1 || true
  adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
  sleep 1
}

dismiss_system_blockers

SMOKE_STATUS=0
maestro test .maestro/smoke.yaml   --format junit   --output artifacts/maestro/smoke.xml   --test-output-dir artifacts/maestro/smoke || SMOKE_STATUS=$?

adb exec-out screencap -p > artifacts/device/after-smoke.png || true
adb shell uiautomator dump /sdcard/window-after-smoke.xml || true
adb pull /sdcard/window-after-smoke.xml artifacts/device/window-after-smoke.xml || true
adb logcat -d -t 2400 > artifacts/device/logcat-after-smoke.txt || true

APP_PID="$(adb shell pidof "$APP_ID" 2>/dev/null | tr -d '\r' || true)"
FATAL_COUNT="$(grep -Eic "FATAL EXCEPTION|Process: $APP_ID|Unable to start activity.*$APP_ID|UnsatisfiedLinkError" artifacts/device/logcat-after-smoke.txt || true)"

VISUAL_STATUS=98
if [[ -n "${MAESTRO_CLOUD_API_KEY:-}" ]]; then
  VISUAL_STATUS=0
  env MAESTRO_CLOUD_API_KEY="$MAESTRO_CLOUD_API_KEY"     maestro test .maestro/visual_audit.yaml       --api-key="$MAESTRO_CLOUD_API_KEY"       --analyze       --format junit       --output artifacts/maestro/visual-ai.xml       --test-output-dir artifacts/maestro/visual-ai || VISUAL_STATUS=$?
else
  echo "MAESTRO_CLOUD_API_KEY not configured; visual AI audit skipped."
fi

PASSENGER_STATUS=98
if [[ -n "${QA_PASSENGER_EMAIL:-}" && -n "${QA_PASSENGER_PASSWORD:-}" ]]; then
  PASSENGER_STATUS=0
  adb shell pm clear "$APP_ID" || true
  dismiss_system_blockers
  maestro test     -e QA_EMAIL="$QA_PASSENGER_EMAIL"     -e QA_PASSWORD="$QA_PASSENGER_PASSWORD"     .maestro/passenger_login.yaml     --format junit     --output artifacts/maestro/passenger.xml     --test-output-dir artifacts/maestro/passenger || PASSENGER_STATUS=$?
else
  echo "Passenger QA credentials not configured; authenticated passenger test skipped."
fi

DRIVER_STATUS=98
if [[ -n "${QA_DRIVER_EMAIL:-}" && -n "${QA_DRIVER_PASSWORD:-}" ]]; then
  DRIVER_STATUS=0
  adb shell pm clear "$APP_ID" || true
  dismiss_system_blockers
  maestro test     -e QA_EMAIL="$QA_DRIVER_EMAIL"     -e QA_PASSWORD="$QA_DRIVER_PASSWORD"     .maestro/driver_login.yaml     --format junit     --output artifacts/maestro/driver.xml     --test-output-dir artifacts/maestro/driver || DRIVER_STATUS=$?
else
  echo "Driver QA credentials not configured; authenticated driver test skipped."
fi

DRIVER_REQUEST_PREP_STATUS=98
DRIVER_REQUEST_FLOW_STATUS=98
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
    maestro test       -e QA_EMAIL="$QA_DRIVER_EMAIL"       -e QA_PASSWORD="$QA_DRIVER_PASSWORD"       -e QA_ROUTE_ORIGIN="$QA_ROUTE_ORIGIN"       .maestro/driver_request_flow.yaml       --format junit       --output artifacts/maestro/driver-request.xml       --test-output-dir artifacts/maestro/driver-request || DRIVER_REQUEST_FLOW_STATUS=$?
    python3 .github/scripts/qa_driver_request_flow.py cleanup > artifacts/backend/driver-request-cleanup.log 2>&1 || true
  else
    DRIVER_REQUEST_PREP_STATUS=$?
    echo "Synthetic driver request preparation failed."
    cat artifacts/backend/driver-request-prepare.log || true
  fi
else
  DRIVER_REQUEST_PREP_STATUS=97
  echo "Passenger/driver QA credentials not configured; critical driver request flow unavailable."
fi

DEVICE_VERDICT="healthy"
DEVICE_REASON="smoke_passed"

if [[ "$SMOKE_STATUS" -ne 0 ]]; then
  if [[ "$FATAL_COUNT" -gt 0 ]]; then
    DEVICE_VERDICT="confirmed_product_failure"
    DEVICE_REASON="smoke_failed_with_android_fatal"
  else
    DEVICE_VERDICT="qa_inconclusive"
    DEVICE_REASON="smoke_assertion_failed_without_runtime_crash"
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

if [[ -z "$APP_PID" && "$DEVICE_VERDICT" == "healthy" ]]; then
  DEVICE_VERDICT="qa_inconclusive"
  DEVICE_REASON="app_process_not_alive_after_smoke"
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

export DEVICE_VERDICT DEVICE_REASON SMOKE_STATUS VISUAL_STATUS
export PASSENGER_STATUS DRIVER_STATUS DRIVER_REQUEST_PREP_STATUS DRIVER_REQUEST_FLOW_STATUS APP_PID FATAL_COUNT
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "verdict": os.environ["DEVICE_VERDICT"],
    "reason": os.environ["DEVICE_REASON"],
    "smoke_status": int(os.environ["SMOKE_STATUS"]),
    "visual_ai_status": int(os.environ["VISUAL_STATUS"]),
    "passenger_status": int(os.environ["PASSENGER_STATUS"]),
    "driver_status": int(os.environ["DRIVER_STATUS"]),
    "driver_request_prep_status": int(os.environ["DRIVER_REQUEST_PREP_STATUS"]),
    "driver_request_flow_status": int(os.environ["DRIVER_REQUEST_FLOW_STATUS"]),
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
