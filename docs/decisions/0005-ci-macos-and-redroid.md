# 0005 — Build on macOS, arm64 only; test Android in Redroid

**Status:** accepted (2026-10-29)

## Context

We want every push to prove that both apps build and that a user can browse with them,
with screenshots in the CI run. Constraints:

- The repository is public, so GitHub's standard hosted runners are free, macOS included.
  `macos-latest` is macOS 26 on an Apple M1 (arm64, 3 CPU, 7 GB).
- Skip expects app builds to happen on a Mac (Xcode, `xcrun`).
- Users run arm64 Android devices. The Android test should exercise the exact APK they
  download, not a variant built for testing.
- GitHub's hosted runners don't expose hardware virtualization to Android emulators:
  - `macos-latest` (M1) has no nested virtualization, so the emulator can't use Apple's
    Hypervisor framework. The android-emulator-runner action's own CI only covers
    `macos-15-intel`.
  - `ubuntu-24.04-arm` has no `/dev/kvm`. We checked: `ls /dev/kvm` fails and `kvm-ok`
    can't load it. GitHub closed the request for it as not planned
    (actions/runner-images#14062).
  - `ubuntu-24.04` (x86_64) does expose KVM.

## Decision

1. **All builds run on `macos-latest`, arm64 only.** CI jobs:
   - **Core:** NSS for macOS, Rust tests, then the generated Swift bindings tested
     against a macOS slice of the Rust core.
   - **iOS:** NSS for iOS, the xcframework, then the app plus its XCUITest on a simulator
     (`xcodebuild test`).
   - **Android:** NSS for Android, `libzen_core.so`, the APK (`skip export`) and the test
     APK. Both APKs are built and debug-signed in the same job.
   - **Screenshots:** publishes each run's end-to-end screenshots.
2. **The Android end-to-end test runs in [Redroid](https://github.com/remote-android/redroid-doc)
   on `ubuntu-24.04-arm`.** Redroid runs Android as a container sharing the host's Linux
   kernel, so there's no VM: arm64 Android runs natively on the arm64 runner. The job
   downloads the APK artifact from the Android job unchanged, starts Redroid
   (`scripts/ci/start-redroid.sh`), and runs the UiAutomator test with `am instrument`
   (`scripts/ci/run-android-e2e.sh`). The runner's kernel ships the Binder module Redroid
   needs.
3. **Both platforms run the same native UI test.** The test launches the app, opens the
   address bar, loads `https://example.com`, waits for the page, checks the page title
   reaches the tab switcher, and opens the Space sheet. It drives the app through SwiftUI
   `accessibilityIdentifier`s, which Skip exposes to Android as Compose test tags /
   resource ids. Tooling: XCUITest on iOS (`app/Darwin/UITests`), UiAutomator on Android
   (`app/Android/app/src/androidTest`).
4. **Screenshots appear inline in the run summary.** The tests save a PNG per step. A
   final job commits them to the `ci-screenshots` branch (one folder per run, newest 30
   kept) and links them from the job summary through `raw.githubusercontent.com`, which
   works because the repository is public.

## What we tried first

| Approach | Result |
|---|---|
| Linux runners for everything, Skip's Linux CLI, a stand-in `xcrun` so Skip's Gradle plugin would run | Worked: APK and Swift cross-compile built on Linux. Dropped once macOS runners turned out to be free: it fought Skip's conventions and needed workarounds (the `xcrun` shim, Linux-only installers). |
| Separate x86_64 APK for an x86_64 emulator on `ubuntu-24.04` (KVM) | Emulator booted and the APKs installed. Rejected: it tests a build users never get, and needs an ABI switch in `ZenCore/Package.swift`. |
| Shipped arm64 APK on the x86_64 emulator via Android's ARM translation (`libndk_translation`) | The app crashed at launch with `UnsatisfiedLinkError` (Skip bridge library didn't load under translation). The same APK runs fine natively, so this was the translation layer, not the app. |
| arm64 emulator on `macos-latest` via android-emulator-runner | No hardware acceleration without nested virtualization; the probe hung booting. Reports show `HVF_UNSUPPORTED`. |
| arm64 emulator on `ubuntu-24.04-arm` | No `/dev/kvm`, so it would fall back to full software emulation. Not attempted beyond confirming KVM is absent. |
| **Redroid on `ubuntu-24.04-arm`** | **Binder module loaded, Android 14 booted in ~5 s, ABIs `arm64-v8a`. The CI APK installed, launched and rendered its start page; the Skip bridge started in 2 ms.** |

## Consequences

- One build platform: no x86_64 builds, no Linux build scripts. Scripts are named for what
  they build: `build-core-apple.sh`, `build-core-android.sh`, `test-swift.sh`, `env.sh`.
- Android is tested on the bytes users install, on the CPU architecture they run.
- Redroid is not a phone. Its graphics are software-rendered (`redroid_gpu_mode=guest`),
  it has no Bluetooth or telephony hardware, and it runs the host's kernel rather than a
  vendor kernel. Good for "does the app start and browse"; device-specific bugs still
  need real phones.
- The Android test depends on GitHub's arm64 kernel keeping the Binder module, and on the
  Redroid image (`redroid/redroid:14.0.0-latest`, overridable via `REDROID_IMAGE`). If
  either goes away, the fallback is the x86_64 emulator with a dedicated x86_64 build.
- macOS runners are slower (3 CPU) than Linux ones and have less disk. NSS builds are
  cached per platform to keep runs reasonable.
- Screenshots depend on the repository staying public. A private repo would need
  artifacts instead of inline images.
- `app/AppIcon.svg` and the vector Android launcher icon were made while icons couldn't
  be generated on Linux. On a Mac, `skip icon` can now replace them with the standard
  icon sets for both platforms.
