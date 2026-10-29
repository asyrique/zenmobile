#!/usr/bin/env bash
# Runs the end-to-end browsing test (app/Android/app/src/androidTest) on the
# device adb is connected to (set ANDROID_SERIAL if there are several), then
# pulls the screenshots and logcat.
#
# Usage: scripts/ci/run-android-e2e.sh <app.apk> <androidTest.apk> <out-dir>
# APP_ID / TEST_ID default to the app's id (Skip.env) and the usual ".test".
set -uo pipefail

APP_APK="$1"; TEST_APK="$2"; OUT="$3"
mkdir -p "$OUT/screenshots"
APP_ID="${APP_ID:-io.github.asyrique.zenmobile}"
TEST_ID="${TEST_ID:-$APP_ID.test}"
echo "app: $APP_ID ($APP_APK), test: $TEST_ID ($TEST_APK)"

adb wait-for-device
adb logcat -c || true
adb install -r -g "$APP_APK"
adb install -r -g "$TEST_APK"

# adb shell hands its arguments to the device's shell as one string, so
# values with spaces need quoting for that shell too.
adb shell am instrument -w -r \
  -e url "'${E2E_URL:-https://example.com}'" \
  -e title "'${E2E_TITLE:-Example Domain}'" \
  "$TEST_ID/androidx.test.runner.AndroidJUnitRunner" | tee "$OUT/instrumentation.txt"

adb pull "/sdcard/Android/data/$APP_ID/files/screenshots/." "$OUT/screenshots/" || true
adb logcat -d > "$OUT/logcat.txt" || true
APP_LOG="$(grep -E "$APP_ID|zen\.mobile|AndroidRuntime|FATAL|GeckoView|Gecko|swift|SkipBridge" "$OUT/logcat.txt" || true)"

# `am instrument` exits 0 even when tests fail; read its report instead.
if grep -q "^OK (" "$OUT/instrumentation.txt"; then
  echo "E2E passed"
else
  echo "E2E failed; app log tail:"
  echo "$APP_LOG" | tail -100
  exit 1
fi
