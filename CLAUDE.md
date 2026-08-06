# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

`flutter` is not on PATH in non-interactive shells on this machine:

```bash
export PATH="$HOME/Coding/SDK/flutter/bin:$PATH"
```

```bash
flutter analyze --fatal-infos          # strict lints; must be zero issues
flutter test                           # full suite
flutter test test/domain/kalman_rssi_smoother_test.dart   # single file
flutter test --coverage && dart run tool/coverage_gate.dart
                                       # gate FAILS below 100% line coverage
                                       # on lib/domain/ + lib/state/ (skips *.g.dart)
dart run build_runner build --delete-conflicting-outputs  # riverpod codegen; commit the .g.dart
flutter test --update-goldens test/ui/radar_golden_test.dart  # regen goldens (test/ui/goldens/)
```

CI (`.github/workflows/ci.yml`) runs analyze + coverage + gate on pushes to `main` and PRs. The Flutter version pinned in `pubspec.yaml` (`environment: flutter:`) is what CI installs and doubles as the golden-renderer pin — keep it in sync with the local SDK.

## Architecture

Spec-driven: `ble-tracker-spec.md` is the authority (FR/NFR numbers referenced in code comments and tests map to it). The layering is strict and every boundary is a Dart `abstract interface class` in `lib/domain/interfaces.dart`:

```
lib/ui/        screens + RadarPainter; consumes providers only
lib/state/     Riverpod providers, DeviceStateComposer, radar blip mapping
lib/domain/    pure logic — no Flutter deps, no I/O, no real timers
lib/platform/  scanner adapters + persistence; the only layer touching plugins
```

Key invariants that hold everywhere and must survive changes:

- **Time is always injected.** Domain/state logic gets time from `ScanObservation.timestamp` and the injected ticker stream (`tickerProvider`), never `DateTime.now()` (one sanctioned exception: radar fade rendering in `radar_screen.dart`). Tests drive time through stream controllers.
- **All tunables live in `ProximityConfig`** (`lib/domain/config.dart`) and are injected — Kalman Q/R, band thresholds, staleness, radar range. Never hard-code them at use sites.
- **`DeviceStateComposer`** (`lib/state/device_state_composer.dart`) is the single source of truth: registry stream × observations × smoothing × staleness ticks → `Map<String, TrackedDeviceState>`. Visibility only becomes `visible` via an observation — registry emissions must not resurrect stale devices.
- **Scanner adapters** (`lib/platform/{fbp,bluez,web,wear}/`) all embed `ScannerStateMachine` (`lib/domain/scanner_state_machine.dart`), which throws on any transition outside spec §5.4. fbp/bluez serialize every state-mutating op through an `_enqueue` queue — a queued op must never call another `_enqueue`-wrapped method (deadlock; the invariant is documented on `_enqueue`). `start`/`stop` from error states are no-ops, never throws.
- **Every adapter must pass the shared contract suite**: call `runBleScannerContract(...)` from `test/contract/ble_scanner_contract.dart` with a `ScannerHarness`. If you add or change adapter behavior, pin it in the contract suite so all five implementations (including `FakeBleScanner`, the reference used by widget tests) stay in lockstep — divergence between the fake and real adapters has caused real bugs here.
- **Plugin API surfaces are isolated** behind thin `*Api` interfaces (`FbpApi`, `BlueZApi`, `WebBluetoothApi`); the `*ApiImpl` classes are deliberately untested (no hardware in CI) — the manual checklist (`docs/manual-test-checklist.md`) covers them per release. Keep them thin.

## Riverpod specifics (pinned versions)

The riverpod family is pinned to an exact set compatible with Dart 3.11 (`flutter_riverpod 3.1.0`, `riverpod_annotation 4.0.0`, `riverpod_generator 4.0.0+1`) — do not bump casually. Conventions forced by these versions:

- `.value` (not `.valueOrNull`) on AsyncValue.
- `Override` imports from `package:flutter_riverpod/misc.dart`.
- `tickerProvider` returns `Raw<Stream<DateTime>>` (raw stream, not AsyncValue-wrapped); tests override it with `overrideWithValue(controller.stream)`.
- Platform-bound providers (`bleScanner`, `deviceRegistry`, `platformCapabilities`, `ticker`) throw `UnimplementedError` unless overridden — real wiring happens in `main.dart` via the conditional-import scanner factories (`scanner_factory_io.dart` / `scanner_factory_web.dart`).

## Tests

Widget tests share helpers exported from `test/ui/device_list_screen_test.dart` (`RecordingRegistry`, `overridesWith`, `dev`) — keep those names public. Tests involving the radar's repeating sweep animation must use bounded `tester.pump(duration)` calls; `pumpAndSettle` never settles there.
