# BLE Proximity Tracker

A Flutter app that listens for Bluetooth Low Energy (BLE) devices around you — headphones, phones, tags — estimates how far away each one is from its signal strength, and shows them on a live radar. It runs on Windows, Linux, Android, Web (Chromium), and Wear OS.

Distance is estimated from RSSI (received signal strength, in dBm), smoothed with a per-device Kalman filter, and grouped into bands: **immediate**, **near**, **mid**, and **far**. Estimates are rough — walls, bodies and antennas all change the signal — so read them as "close", "across the room", or "far away", not as metres.

## Documentation map

| Document | What it is for | Status |
|---|---|---|
| **This README** | Start here: run it, use it, find your way around | Current |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the pieces fit together, and the rules the code must keep | Current |
| [CLAUDE.md](CLAUDE.md) | Working notes for contributors and AI coding assistants: commands, conventions, invariants | Current |
| [ble-tracker-spec.md](ble-tracker-spec.md) | The functional specification. FR/NFR numbers in code and tests refer to it | Authoritative; open questions resolved inline |
| [docs/manual-test-checklist.md](docs/manual-test-checklist.md) | Hardware checks to run per release (automated tests cannot cover them) | Current |
| [docs/superpowers/plans/2026-08-06-ble-tracker-v1.md](docs/superpowers/plans/2026-08-06-ble-tracker-v1.md) | The v1 build plan. Historical: kept for the reasoning behind decisions | Historical |

Open work is tracked as GitHub issues: <https://github.com/matella/ble-tracker/issues>.

## Quick start

### 1. Install the tools

- **Git**, and a GitHub account with access to the repository.
- **Flutter 3.47.7**, the version pinned in `pubspec.yaml`. Check with `flutter --version`. A different Flutter version can change the golden (screenshot) tests, so match the pin.
- Per platform:
  - **Windows desktop:** Visual Studio 2022 or later with the "Desktop development with C++" workload. Also turn on **Developer Mode** (`start ms-settings:developers`): plugins are linked with symlinks, and the build fails without it.
  - **Android:** Android Studio (for the SDK), then accept the licences with `flutter doctor --android-licenses`. Use JDK 21.
  - **Linux:** BlueZ 5.60 or newer, and the GTK build dependencies that `flutter doctor` lists.
  - **Web:** Google Chrome or Chromium.
  - **Wear OS:** a Wear OS 4+ watch with developer options enabled.

Run `flutter doctor -v` and fix anything it marks with a cross before continuing.

### 2. Get the code and run it

```bash
git clone https://github.com/matella/ble-tracker.git
cd ble-tracker
flutter pub get
flutter run -d windows        # or: -d linux, -d chrome, -d <android-device-id>
```

Check which devices are available with `flutter devices`.

Other targets:

```bash
flutter run -d chrome                                      # Web (Tier C: manual pairing)
flutter run -d <watch-id> --dart-define=WEAR_OS=true       # Wear OS build of the Android module
```

You only need code generation (`dart run build_runner build`) if you change a file that uses Riverpod annotations. The generated `*.g.dart` files are committed, so a fresh clone runs without it.

## Using the app

The app has three tabs at the bottom.

- **Radar** — every registered device that is currently visible appears as a dot. The ring closest to the centre is "immediate" (under 0.5 m), then "near" (under 3 m), then "mid" (up to 10 m). Anything between the mid ring and the edge is "far" (the edge is about 20 m). Tap a dot for its details.
- **Devices** — your registered devices, each with its distance and band, or "Not visible" / "Tracking off". The toggle switches tracking on or off per device. The gear icon opens **Settings**.
- **Discover** — devices the app has just heard that you haven't registered yet. Press **Track** to add one to your devices. Only devices in range and advertising appear here.

Two things worth knowing:

- **The angle of a dot means nothing.** Each device gets a fixed, arbitrary angle so dots don't overlap. Only the distance from the centre is meaningful.
- **A device shows as "Not visible" when it stops advertising for 10 seconds.** Many devices advertise only occasionally, so a quiet device is not necessarily far away.

### Settings

**Environment factor (n)** sets how fast the signal fades with distance: about 2.0 in open air, 2.7 to 3.0 indoors, up to 4.0 behind heavy obstruction. Changing it restarts smoothing, so devices show as "Not visible" until heard again.

### Calibrating a device

For better accuracy, calibrate a device you own. Open its details, stand exactly 1 metre from it, and press **Calibrate at 1 m**. The app averages about 5 seconds of readings and offers to save them as that device's reference signal strength at 1 m. **Reset** goes back to the advertised value.

Calibration is only offered while the device is visible.

### Platform tiers

What the app can do depends on the platform. The app adapts automatically.

| Tier | Platforms | What you get |
|---|---|---|
| **A** (full) | Android 12+, Windows 10 21H2+, macOS 13+, Linux (BlueZ 5.60+) | Continuous scanning and automatic discovery of nearby devices. Desktop keeps scanning when minimised. Android keeps scanning in the background with a notification. |
| **B** (reduced background) | iOS 16+, Wear OS 4+ | Full use while the app is open. The OS throttles background scanning, and the app says so when you come back. On a watch, scanning drops to a slower mode in ambient (wrist-down) display. |
| **C** (manual only) | Web in Chromium | You pair devices yourself through the browser's device chooser, and the app polls their signal strength. Scanning pauses while the browser tab is hidden. Safari shows an unsupported-browser message. |

**Android limit:** while the app is in the background, it scans only your registered devices, which lets it keep getting results with the screen off. That filter matches MAC addresses. Devices with rotating private addresses (most phones and many wearables) may not be seen with the screen off. Tags with a fixed address work.

## How it works

The data path, from radio to screen:

1. **Scan.** The platform's BLE stack reports advertisements: device ID, RSSI, and TxPower when the device includes it.
2. **Smooth.** Each device has its own Kalman filter, which steadies the jumpy raw RSSI values.
3. **Estimate distance.** The log-distance path-loss model:

   ```
   distance (m) = 10 ^ ((TxPower − RSSI) / (10 × n))
   ```

   TxPower is the device's calibrated reference at 1 m if you calibrated it, otherwise the advertised value, otherwise −59 dBm. `n` is the environment factor from Settings.
4. **Band.** The distance maps to immediate / near / mid / far.
5. **Show.** The radar places each dot: radius from the distance on a log scale (so near devices spread out), angle fixed per device.

The **device state** — visible, not visible, or tracking off — is decided in one place (`lib/state/device_state_composer.dart`). A device becomes visible only when it is observed, and goes "Not visible" after 10 seconds without an observation.

The distance is an estimate with real error. The main sources are the TxPower a device advertises (often wrong), obstacles between you and the device, and the device's own antenna. Calibration removes most of the TxPower error for a device you own.

## Repository map

```
lib/
  main.dart           start-up: wires platform scanners and storage into providers
  ui/                 screens: radar, device list, discovery, settings, detail sheet
  state/              Riverpod providers and the device-state composer
  domain/             pure logic, no Flutter, no I/O: distance, smoothing, registry,
                      radar layout, scanner state machine, settings, calibration
  platform/           the only code that touches plugins and the OS
    fbp/              flutter_blue_plus (Android, iOS, macOS, Windows)
    bluez/            BlueZ over D-Bus (Linux)
    web/              Web Bluetooth (Chrome)
    wear/             Wear OS wrapper and ambient-mode channel
    android/          Android background-scan channel
android/app/src/main/kotlin/   Android host: MainActivity, background service
test/
  domain/ state/ platform/ ui/  unit and widget tests
  contract/           the shared scanner contract every adapter must pass
  ui/goldens/         screenshot references for the radar
tool/coverage_gate.dart   fails the build below 100% coverage on domain/ and state/
docs/                 checklist, architecture, historical plan
```

## Testing

```bash
flutter analyze --fatal-infos            # must report zero issues
flutter test                             # the whole suite
flutter test test/domain/kalman_rssi_smoother_test.dart   # one file
flutter test --coverage && dart run tool/coverage_gate.dart
flutter test --update-goldens test/ui/radar_golden_test.dart   # after an intended visual change
```

Automated tests cover logic, the screens, and every scanner adapter's contract. They can't cover real radios, so the [manual checklist](docs/manual-test-checklist.md) is run by hand per release.

CI (`.github/workflows/ci.yml`) runs on every push to `main` and every pull request:

- **Ubuntu:** analyze, tests, the coverage gate, and the radar hash test under Chrome.
- **Windows:** analyze, tests, the coverage gate, and `flutter build windows`.
- **Android:** builds the debug APK for the phone and for Wear OS. Compile-only: nothing runs on a device.

## Contributing

1. Create a branch from `main`. Keep one concern per branch.
2. Make the change. Keep time injected, tunables in `ProximityConfig`, and adapters thin: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) lists the rules.
3. Run `flutter analyze --fatal-infos` and the tests. Any new code in `lib/domain/` or `lib/state/` must be fully covered; the gate enforces it.
4. Open a PR. Describe what was checked on real hardware, and what wasn't. If the change needs a device test, add a line to the manual checklist.
5. Wait for CI to pass before merging.

The commit style is conventional commits (`feat:`, `fix:`, `ci:`, `docs:`, `chore:`).

## Troubleshooting

- **The Windows build fails with "Building with plugins requires symlink support."** Turn on Developer Mode (`start ms-settings:developers`).
- **The Radar or Devices tab shows a red or orange banner.** Bluetooth is off, or the app doesn't have the Bluetooth permission. Turn Bluetooth on, or grant the permission in system settings. The banner clears on its own.
- **Discover stays empty.** Discover only lists devices being advertised right now. Check the banner first, then make sure the device is advertising (for example, put earbuds into pairing mode).
- **Android: no devices appear with the screen off.** See the Android limit above. Tags with fixed addresses are the reliable test.
- **Web: nothing happens when I press Pair.** Use Chrome or Edge on a secure origin (`localhost` works). Safari does not support Web Bluetooth.
- **Flutter says a licence is missing (Android).** Run `flutter doctor --android-licenses` and accept the prompts.
