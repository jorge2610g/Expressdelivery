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

SMOKE_STATUS=0
maestro test .maestro/smoke.yaml   --format junit   --output artifacts/maestro/smoke.xml   --test-output-dir artifacts/maestro/smoke || SMOKE_STATUS=$?

adb exec-out screencap -p > artifacts/device/after-smoke.png || true
adb shell uiautomator dump /sdcard/window-after-smoke.xml || true
adb pull /sdcard/window-after-smoke.xml artifacts/device/window-after-smoke.xml || true
adb logcat -d -t 2400 > artifacts/device/logcat-after-smoke.txt || true

APP_PID="$(adb shell pidof "$APP_ID" 2>/dev/null | tr -d '\r' || true)"
FATAL_COUNT="$(grep -Eic "FATAL EXCEPTION|Process: $APP_ID|Unable to start activity.*$APP_ID|UnsatisfiedLinkError" artifacts/device/logcat-after-smoke.txt || true)"

VISUAL_STATUS=0
if [[ -n "${MAESTRO_CLOUD_API_KEY:-}" ]]; then
  env MAESTRO_CLOUD_API_KEY="$MAESTRO_CLOUD_API_KEY"     maestro test .maestro/visual_audit.yaml       --api-key="$MAESTRO_CLOUD_API_KEY"       --analyze       --format junit       --output artifacts/maestro/visual-ai.xml       --test-output-dir artifacts/maestro/visual-ai || VISUAL_STATUS=$?
else
  echo "MAESTRO_CLOUD_API_KEY not configured; visual AI audit skipped."
fi

PASSENGER_STATUS=0
if [[ -n "${QA_PASSENGER_EMAIL:-}" && -n "${QA_PASSENGER_PASSWORD:-}" ]]; then
  adb shell pm clear "$APP_ID" || true
  maestro test     -e QA_EMAIL="$QA_PASSENGER_EMAIL"     -e QA_PASSWORD="$QA_PASSENGER_PASSWORD"     .maestro/passenger_login.yaml     --format junit     --output artifacts/maestro/passenger.xml     --test-output-dir artifacts/maestro/passenger || PASSENGER_STATUS=$?
else
  echo "Passenger QA credentials not configured; authenticated passenger test skipped."
fi

DRIVER_STATUS=0
if [[ -n "${QA_DRIVER_EMAIL:-}" && -n "${QA_DRIVER_PASSWORD:-}" ]]; then
  adb shell pm clear "$APP_ID" || true
  maestro test     -e QA_EMAIL="$QA_DRIVER_EMAIL"     -e QA_PASSWORD="$QA_DRIVER_PASSWORD"     .maestro/driver_login.yaml     --format junit     --output artifacts/maestro/driver.xml     --test-output-dir artifacts/maestro/driver || DRIVER_STATUS=$?
else
  echo "Driver QA credentials not configured; authenticated driver test skipped."
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

# Visual AI is advisory: one AI judgment is not enough to mark Express broken.
if [[ "$VISUAL_STATUS" -ne 0 && "$DEVICE_VERDICT" == "healthy" ]]; then
  DEVICE_VERDICT="warning"
  DEVICE_REASON="visual_ai_requires_review"
fi

# Authenticated screen assertions are advisory until the full synthetic flow is
# correlated against app_flow_events. They never create a regression by themselves.
if [[ "$PASSENGER_STATUS" -ne 0 || "$DRIVER_STATUS" -ne 0 ]]; then
  if [[ "$DEVICE_VERDICT" == "healthy" ]]; then
    DEVICE_VERDICT="warning"
    DEVICE_REASON="authenticated_smoke_requires_review"
  fi
fi

export DEVICE_VERDICT DEVICE_REASON SMOKE_STATUS VISUAL_STATUS
export PASSENGER_STATUS DRIVER_STATUS APP_PID FATAL_COUNT
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
    "app_process_alive": bool(os.environ.get("APP_PID", "").strip()),
    "android_fatal_evidence_count": int(os.environ["FATAL_COUNT"]),
}
Path("artifacts/backend/device-verdict.json").write_text(
    json.dumps(payload, indent=2, ensure_ascii=False)
)
print(json.dumps(payload, ensure_ascii=False))
PY

# Never make the product red from a single UI/AI assertion here.
# The workflow evidence gate decides after combining device + backend evidence.
exit 0
