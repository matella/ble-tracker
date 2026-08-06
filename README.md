# BLE Proximity Tracker

A multi-platform Flutter app that tracks the proximity of Bluetooth Low Energy devices — headphones, phones, tags — and displays them on a live radar. Distance is estimated from signal strength (RSSI), smoothed with a per-device Kalman filter, and rendered in real time with qualitative bands (`immediate` / `near` / `mid` / `far`).

Built spec-first: see [ble-tracker-spec.md](ble-tracker-spec.md) for the full functional specification, and the [implementation plan](docs/superpowers/plans/2026-08-06-ble-tracker-v1.md) for how v1 was broken down and built.

## Platform support

| Tier | Platforms | Capabilities |
|---|---|---|
| A (full) | Android 12+, Windows 10 21H2+, macOS 13+, Linux (BlueZ 5.60+) | Continuous scan, auto-discovery, background |
| B (reduced background) | iOS 16+, Wear OS 4+ | Full foreground; OS-throttled background |
| C (manual-only) | Web (Chromium only) | Manual pairing via browser chooser; RSSI polling. Safari shows an unsupported-browser message |

The UI adapts to the running tier automatically (e.g. Web shows a "Pair a device" button instead of auto-discovery).

## Architecture

Strict layering, every boundary an `abstract interface class`:

```
lib/ui/        widgets, radar painter, screens
lib/state/     Riverpod providers, device state composer, blip mapping
lib/domain/    pure logic: Kalman smoother, distance estimator,
               radar layout, registry, scanner state machine
lib/platform/  BLE adapters (flutter_blue_plus, BlueZ, Web Bluetooth,
               Wear wrapper), persistence
```

All four scanner adapters pass a shared contract test suite ([test/contract/](test/contract/)). Time is injected everywhere — no real timers in domain or state logic.

## Development

Requires Flutter 3.41.2 (pinned in `pubspec.yaml` — the pin doubles as the golden-test renderer pin).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # riverpod codegen
flutter run
```

Wear OS builds use the same Android module with `--dart-define=WEAR_OS=true`.

## Testing

```bash
flutter analyze --fatal-infos
flutter test --coverage
dart run tool/coverage_gate.dart   # fails below 100% on lib/domain/ + lib/state/
```

CI runs all three on every push to `main` and every pull request. Golden tests live under [test/ui/goldens/](test/ui/goldens/); regenerate with `flutter test --update-goldens test/ui/radar_golden_test.dart`.

There are no hardware integration tests by design — the gap is covered by the contract suites plus the per-release [manual test checklist](docs/manual-test-checklist.md).

## Project tracking

Work is tracked on the [BLE Tracker project board](https://github.com/users/matella/projects/1). Known v1 descopes (settings UI for the path-loss factor, Web page-visibility handling) are documented in the plan and filed as issues.
