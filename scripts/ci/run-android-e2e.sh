#!/usr/bin/env bash
# Runs the end-to-end browsing test (app/Android/app/src/androidTest) on a
# booted emulator, then pulls the screenshots and logcat.
#
# Usage: scripts/ci/run-android-e2e.sh <app.apk> <androidTest.apk> <out-dir>
set -uo pipefail

APP_APK="$1"; TEST_APK="$2"; OUT="$3"
mkdir -p "$OUT/screenshots"
AAPT2="$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)aapt2"
APP_ID="$("$AAPT2" dump packagename "$APP_APK")"
TEST_ID="$("$AAPT2" dump packagename "$TEST_APK")"
echo "app: $APP_ID, test: $TEST_ID"

adb wait-for-device
adb logcat -c || true
adb install -r -g "$APP_APK"
adb install -r -g "$TEST_APK"

adb shell am instrument -w -r \
  -e url "${E2E_URL:-https://example.com}" \
  -e title "${E2E_TITLE:-Example Domain}" \
  "$TEST_ID/androidx.test.runner.AndroidJUnitRunner" | tee "$OUT/instrumentation.txt"

adb pull "/sdcard/Android/data/$APP_ID/files/screenshots/." "$OUT/screenshots/" || true
adb logcat -d > "$OUT/logcat.txt" || true

# `am instrument` exits 0 even when tests fail; read its report instead.
if grep -q "^OK (" "$OUT/instrumentation.txt"; then
  echo "E2E passed"
else
  echo "E2E failed; app log tail:"
  grep -iE "zen|gecko|swift|FATAL|AndroidRuntime" "$OUT/logcat.txt" | tail -80
  exit 1
fi
