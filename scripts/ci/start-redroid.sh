#!/usr/bin/env bash
# Starts Android (Redroid: Android in a container, sharing the host kernel)
# on an arm64 Linux runner and connects adb to it. arm64 apps run natively;
# no emulator, no KVM. Needs the kernel's binder module (GitHub's
# ubuntu-24.04-arm kernel ships it).
#
# Usage: scripts/ci/start-redroid.sh   (then: export ANDROID_SERIAL=localhost:5555)
set -euo pipefail

IMAGE="${REDROID_IMAGE:-redroid/redroid:14.0.0-latest}"

sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
command -v adb > /dev/null || sudo apt-get install -y -q adb > /dev/null

docker run -d --privileged --name redroid -p 5555:5555 "$IMAGE" \
  androidboot.redroid_gpu_mode=guest \
  androidboot.redroid_width=1080 androidboot.redroid_height=2340 androidboot.redroid_dpi=420

for i in $(seq 1 60); do
  adb connect localhost:5555 > /dev/null 2>&1 || true
  if [[ "$(adb -s localhost:5555 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    echo "Android $(adb -s localhost:5555 shell getprop ro.build.version.release | tr -d '\r') booted after $((i * 5))s," \
      "ABIs: $(adb -s localhost:5555 shell getprop ro.product.cpu.abilist | tr -d '\r')"
    exit 0
  fi
  sleep 5
done
echo "Redroid did not boot" >&2
docker logs redroid 2>&1 | tail -50 >&2
exit 1
