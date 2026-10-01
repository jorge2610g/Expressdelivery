#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/maestro artifacts/device

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

VISUAL_STATUS=0
if [[ -n "${MAESTRO_CLOUD_API_KEY:-}" ]]; then
  maestro test .maestro/visual_audit.yaml     --api-key="$MAESTRO_CLOUD_API_KEY"     --analyze     --format junit     --output artifacts/maestro/visual-ai.xml     --test-output-dir artifacts/maestro/visual-ai || VISUAL_STATUS=$?
else
  echo "MAESTRO_CLOUD_API_KEY not configured; visual AI audit skipped."
fi

if [[ -n "${QA_PASSENGER_EMAIL:-}" && -n "${QA_PASSENGER_PASSWORD:-}" ]]; then
  adb shell pm clear "$APP_ID" || true
  maestro test     -e QA_EMAIL="$QA_PASSENGER_EMAIL"     -e QA_PASSWORD="$QA_PASSENGER_PASSWORD"     .maestro/passenger_login.yaml     --format junit     --output artifacts/maestro/passenger.xml     --test-output-dir artifacts/maestro/passenger
else
  echo "Passenger QA credentials not configured; authenticated passenger test skipped."
fi

if [[ -n "${QA_DRIVER_EMAIL:-}" && -n "${QA_DRIVER_PASSWORD:-}" ]]; then
  adb shell pm clear "$APP_ID" || true
  maestro test     -e QA_EMAIL="$QA_DRIVER_EMAIL"     -e QA_PASSWORD="$QA_DRIVER_PASSWORD"     .maestro/driver_login.yaml     --format junit     --output artifacts/maestro/driver.xml     --test-output-dir artifacts/maestro/driver
else
  echo "Driver QA credentials not configured; authenticated driver test skipped."
fi

echo "Express QA result: smoke=$SMOKE_STATUS visual_ai=$VISUAL_STATUS"

if [[ "$SMOKE_STATUS" -ne 0 || "$VISUAL_STATUS" -ne 0 ]]; then
  exit 1
fi
