# BLE Proximity Tracker v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full v1 of the BLE proximity tracker per `ble-tracker-spec.md`: live radar UI, Kalman-smoothed RSSI distance estimation, device registry, and scanner adapters for all seven target platforms.

**Architecture:** Strict layering `ui → state → domain → platform`; every boundary is a Dart `abstract interface class` defined before implementation. All logic lives in pure, injectable domain classes (no timers, no I/O); platform adapters are thin translators verified by a shared contract test suite.

**Tech Stack:** Flutter (stable channel), Riverpod with code-gen providers, flutter_blue_plus (Android/iOS/macOS/Windows), bluez (Linux), flutter_web_bluetooth (Web), shared_preferences (registry persistence), fake_async for time control in tests.

## Global Constraints

- Min OS versions: Android 12 (API 31), iOS 16, Wear OS 4, Windows 10 21H2+, macOS 13, Linux BlueZ 5.60+, Web Chromium-only (Safari must show unsupported message).
- Kalman defaults: process noise `Q = 0.065`, measurement noise `R = 1.4` — MUST be injected, never hard-coded.
- Path loss model: `d = 10 ^ ((TxPower − RSSI) / (10 · n))`; `n` default `2.7`, user-tunable range `2.0–4.0`.
- Band thresholds (config constants, injected): `immediate` < 0.5 m, `near` 0.5–3 m, `mid` 3–10 m, `far` > 10 m. Exactly 0.5 → near; exactly 3.0 → mid; exactly 10.0 → mid.
- `T_stale = 10 s` (config); blip fade-out over 2 s.
- No cap on registered or tracked devices.
- Blip angle: deterministic stable hash of device ID; no directional meaning implied.
- Coverage gate: 100% line coverage on `lib/domain/` and `lib/state/`; `flutter analyze` with zero warnings.
- No integration tests; gap covered by unit + contract + widget/golden tests + manual checklist.
- No real timers or clocks in domain/state logic — time always injected.
- Scan profiles: `lowLatency` only while radar screen visible; `balanced` on list screen (NFR-4).

**Naming used throughout (later tasks depend on these exact names):**
`ProximityConfig`, `ScanObservation`, `DistanceEstimate`, `ProximityBand`, `RegisteredDevice`, `DeviceType`, `TrackedDeviceState`, `DeviceVisibility`, `ScannerStatus`, `ScanProfile`, `CapabilityTier`, `BleScanner`, `RssiSmoother`, `DistanceEstimator`, `DeviceRegistry`, `RadarLayout`, `PlatformCapabilities`, `KalmanRssiSmoother`, `LogDistanceEstimator`, `HashRadarLayout`, `ScannerStateMachine`, `ScannerEvent`, `KeyValueStore`, `PersistentDeviceRegistry`, `DeviceStateComposer`, `RadarBlip`, `radarBlipsFrom`, `hitTestBlips`.

**Execution notes for every task:** run commands from the repo root. After each task's final green test run, also run `flutter analyze` and fix any warnings before committing. When a task touches Riverpod code-gen files, run `dart run build_runner build --delete-conflicting-outputs` before testing.

---

### Task 1: Project scaffold, strict lints, CI skeleton

**Files:**
- Create: Flutter scaffold at repo root (via `flutter create`)
- Create: `analysis_options.yaml` (overwrite generated one)
- Create: `.github/workflows/ci.yml`
- Modify: `pubspec.yaml` (via `flutter pub add`)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a building Flutter app named `ble_tracker`; CI running analyze + tests; all dependencies later tasks import.

- [ ] **Step 1: Scaffold the Flutter project**

```bash
flutter create . --project-name ble_tracker --org com.matella --platforms=android,ios,macos,windows,linux,web
```

Expected: `lib/main.dart` and platform folders created. (Wear OS ships from the same Android module; no separate platform folder.)

- [ ] **Step 2: Add dependencies**

```bash
flutter pub add flutter_riverpod riverpod_annotation flutter_blue_plus shared_preferences bluez flutter_web_bluetooth collection
flutter pub add --dev riverpod_generator build_runner riverpod_lint custom_lint fake_async
```

Expected: all resolve without version conflicts. If `flutter_web_bluetooth` fails to resolve, check its pub.dev page for the current name/constraint before substituting anything.

- [ ] **Step 3: Replace `analysis_options.yaml` with strict config**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    todo: error
  plugins:
    - custom_lint

linter:
  rules:
    - always_declare_return_types
    - prefer_final_locals
    - unawaited_futures
    - directives_ordering
```

- [ ] **Step 4: Verify baseline is green**

Run: `flutter analyze && flutter test`
Expected: analyze passes with no issues; the generated `widget_test.dart` passes. If the generated counter test fails because we will replace `main.dart` later, leave it for now — it must pass at this step.

- [ ] **Step 5: Create CI workflow `.github/workflows/ci.yml`**

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version-file: pubspec.yaml
          cache: true
      - run: flutter pub get
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
```

Note: `flutter-version-file: pubspec.yaml` requires an `environment: flutter:` pin — add the exact local version from `flutter --version --machine` (key `flutterVersion`) to `pubspec.yaml`:

```yaml
environment:
  sdk: ^3.5.0   # keep whatever flutter create generated
  flutter: 3.35.0  # replace with local flutter --version output
```

The pinned version doubles as the golden-test renderer pin (§7.6).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter app with strict lints and CI"
```

---

### Task 2: Config, core data types, domain interfaces

**Files:**
- Create: `lib/domain/config.dart`
- Create: `lib/domain/types.dart`
- Create: `lib/domain/interfaces.dart`
- Test: `test/domain/types_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: every type and abstract interface listed in Global Constraints naming; all later tasks import from these three files.

- [ ] **Step 1: Write the failing test**

`test/domain/types_test.dart`:

```dart
import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProximityConfig defaults match spec', () {
    const c = ProximityConfig();
    expect(c.processNoise, 0.065);
    expect(c.measurementNoise, 1.4);
    expect(c.environmentFactor, 2.7);
    expect(c.defaultTxPower, -59.0);
    expect(c.immediateMaxMeters, 0.5);
    expect(c.nearMaxMeters, 3.0);
    expect(c.midMaxMeters, 10.0);
    expect(c.staleAfter, const Duration(seconds: 10));
    expect(c.blipFadeOut, const Duration(seconds: 2));
  });

  test('ProximityConfig rejects environment factor outside 2.0-4.0', () {
    expect(() => ProximityConfig(environmentFactor: 1.9), throwsArgumentError);
    expect(() => ProximityConfig(environmentFactor: 4.1), throwsArgumentError);
    expect(ProximityConfig(environmentFactor: 2.0).environmentFactor, 2.0);
    expect(ProximityConfig(environmentFactor: 4.0).environmentFactor, 4.0);
  });

  test('RegisteredDevice JSON roundtrip', () {
    const d = RegisteredDevice(
      id: 'aa:bb',
      name: 'Buds',
      type: DeviceType.headphones,
      trackingEnabled: false,
    );
    expect(RegisteredDevice.fromJson(d.toJson()), d);
  });

  test('value equality on core types', () {
    expect(
      const DistanceEstimate(meters: 1.5, band: ProximityBand.near),
      const DistanceEstimate(meters: 1.5, band: ProximityBand.near),
    );
    final t = DateTime.utc(2026);
    expect(
      ScanObservation(deviceId: 'x', rssi: -60, txPower: -59, timestamp: t, advertisedName: 'n'),
      ScanObservation(deviceId: 'x', rssi: -60, txPower: -59, timestamp: t, advertisedName: 'n'),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/types_test.dart`
Expected: FAIL — files don't exist.

- [ ] **Step 3: Implement `lib/domain/config.dart`**

```dart
/// All tunable constants (FR-9, FR-10, FR-11, FR-12). Injected everywhere —
/// never hard-code these values at use sites.
class ProximityConfig {
  const ProximityConfig({
    this.processNoise = 0.065,
    this.measurementNoise = 1.4,
    this.environmentFactor = 2.7,
    this.defaultTxPower = -59.0,
    this.immediateMaxMeters = 0.5,
    this.nearMaxMeters = 3.0,
    this.midMaxMeters = 10.0,
    this.staleAfter = const Duration(seconds: 10),
    this.blipFadeOut = const Duration(seconds: 2),
    this.radarMinMeters = 0.1,
    this.radarMaxMeters = 20.0,
  }) : assert(
          environmentFactor >= 2.0 && environmentFactor <= 4.0,
          'environmentFactor must be in [2.0, 4.0]',
        );

  final double processNoise;
  final double measurementNoise;
  final double environmentFactor;
  final double defaultTxPower;
  final double immediateMaxMeters;
  final double nearMaxMeters;
  final double midMaxMeters;
  final Duration staleAfter;
  final Duration blipFadeOut;
  final double radarMinMeters;
  final double radarMaxMeters;
}
```

Note: `assert` is compiled out in release mode, and the test expects `ArgumentError` — use a factory-check instead:

```dart
class ProximityConfig {
  ProximityConfig({
    this.processNoise = 0.065,
    this.measurementNoise = 1.4,
    this.environmentFactor = 2.7,
    this.defaultTxPower = -59.0,
    this.immediateMaxMeters = 0.5,
    this.nearMaxMeters = 3.0,
    this.midMaxMeters = 10.0,
    this.staleAfter = const Duration(seconds: 10),
    this.blipFadeOut = const Duration(seconds: 2),
    this.radarMinMeters = 0.1,
    this.radarMaxMeters = 20.0,
  }) {
    if (environmentFactor < 2.0 || environmentFactor > 4.0) {
      throw ArgumentError.value(
        environmentFactor, 'environmentFactor', 'must be in [2.0, 4.0]');
    }
  }
  // ... same final fields as above
}
```

(Drop `const` from the constructor; the types test uses `const ProximityConfig()` in the defaults test — change that test line to non-const `ProximityConfig()` to match.)

- [ ] **Step 4: Implement `lib/domain/types.dart`**

```dart
enum ProximityBand { immediate, near, mid, far }

enum DeviceVisibility { visible, notVisible, trackingOff }

enum ScannerStatus { idle, scanning, unavailable, unauthorized }

enum ScanProfile { lowLatency, balanced }

enum CapabilityTier { tierA, tierB, tierC }

enum DeviceType { headphones, phone, tag, watch, other }

class ScanObservation {
  const ScanObservation({
    required this.deviceId,
    required this.rssi,
    required this.timestamp,
    this.txPower,
    this.advertisedName,
  });

  final String deviceId;
  final double rssi;
  final double? txPower;
  final DateTime timestamp;
  final String? advertisedName;

  @override
  bool operator ==(Object other) =>
      other is ScanObservation &&
      other.deviceId == deviceId &&
      other.rssi == rssi &&
      other.txPower == txPower &&
      other.timestamp == timestamp &&
      other.advertisedName == advertisedName;

  @override
  int get hashCode => Object.hash(deviceId, rssi, txPower, timestamp, advertisedName);
}

class DistanceEstimate {
  const DistanceEstimate({required this.meters, required this.band});

  final double meters;
  final ProximityBand band;

  @override
  bool operator ==(Object other) =>
      other is DistanceEstimate && other.meters == meters && other.band == band;

  @override
  int get hashCode => Object.hash(meters, band);
}

class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.name,
    required this.type,
    this.trackingEnabled = true,
  });

  factory RegisteredDevice.fromJson(Map<String, Object?> json) =>
      RegisteredDevice(
        id: json['id']! as String,
        name: json['name']! as String,
        type: DeviceType.values.byName(json['type']! as String),
        trackingEnabled: json['trackingEnabled']! as bool,
      );

  final String id;
  final String name;
  final DeviceType type;
  final bool trackingEnabled;

  RegisteredDevice copyWith({String? name, bool? trackingEnabled}) =>
      RegisteredDevice(
        id: id,
        name: name ?? this.name,
        type: type,
        trackingEnabled: trackingEnabled ?? this.trackingEnabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'trackingEnabled': trackingEnabled,
      };

  @override
  bool operator ==(Object other) =>
      other is RegisteredDevice &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.trackingEnabled == trackingEnabled;

  @override
  int get hashCode => Object.hash(id, name, type, trackingEnabled);
}

class TrackedDeviceState {
  const TrackedDeviceState({
    required this.device,
    required this.visibility,
    this.estimate,
    this.lastSeen,
  });

  final RegisteredDevice device;
  final DeviceVisibility visibility;
  final DistanceEstimate? estimate;
  final DateTime? lastSeen;

  @override
  bool operator ==(Object other) =>
      other is TrackedDeviceState &&
      other.device == device &&
      other.visibility == visibility &&
      other.estimate == estimate &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(device, visibility, estimate, lastSeen);
}
```

- [ ] **Step 5: Implement `lib/domain/interfaces.dart`** (verbatim from spec §5.1/§5.2)

```dart
import 'types.dart';

/// Emits raw scan observations. Implemented per platform tier.
abstract interface class BleScanner {
  Stream<ScanObservation> observe(); // never errors; state via ScannerStatus
  Stream<ScannerStatus> status(); // idle / scanning / unavailable / unauthorized
  Future<void> start(ScanProfile profile); // profile: lowLatency | balanced
  Future<void> stop();
}

/// Pure function boundary — fully unit-testable, no I/O.
abstract interface class RssiSmoother {
  double next(String deviceId, double rawRssi, DateTime at);
  void reset(String deviceId);
}

abstract interface class DistanceEstimator {
  DistanceEstimate estimate({
    required double smoothedRssi,
    required double txPower,
    required double environmentFactor,
  });
}

abstract interface class DeviceRegistry {
  Stream<List<RegisteredDevice>> watchAll();
  Future<void> register(RegisteredDevice device);
  Future<void> setTracking(String deviceId, bool enabled);
  Future<void> rename(String deviceId, String name);
  Future<void> remove(String deviceId);
}

abstract interface class RadarLayout {
  /// Deterministic: same id → same angle, always.
  double angleFor(String deviceId);

  /// Log-scaled radial position in [0, 1] from distance + band config.
  double radiusFor(DistanceEstimate estimate);
}

abstract interface class PlatformCapabilities {
  CapabilityTier get tier; // tierA | tierB | tierC
  bool get supportsAutoDiscovery;
  bool get supportsBackgroundScan;
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/domain/types_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat: add config, core types, and domain interfaces"
```

---

### Task 3: Kalman RSSI smoother

**Files:**
- Create: `lib/domain/kalman_rssi_smoother.dart`
- Test: `test/domain/kalman_rssi_smoother_test.dart`

**Interfaces:**
- Consumes: `RssiSmoother` from `lib/domain/interfaces.dart`
- Produces: `KalmanRssiSmoother({required double processNoise, required double measurementNoise}) implements RssiSmoother`

- [ ] **Step 1: Write the failing test**

`test/domain/kalman_rssi_smoother_test.dart`:

```dart
import 'dart:math';

import 'package:ble_tracker/domain/kalman_rssi_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

KalmanRssiSmoother defaultSmoother() =>
    KalmanRssiSmoother(processNoise: 0.065, measurementNoise: 1.4);

double variance(List<double> xs) {
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  return xs.map((x) => pow(x - mean, 2).toDouble()).reduce((a, b) => a + b) /
      xs.length;
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  test('converges on a constant signal', () {
    final s = defaultSmoother();
    var out = 0.0;
    for (var i = 0; i < 50; i++) {
      out = s.next('d', -60, t0.add(Duration(milliseconds: 100 * i)));
    }
    expect(out, closeTo(-60, 0.01));
  });

  test('attenuates jitter (output variance well below input variance)', () {
    final s = defaultSmoother();
    final inputs = <double>[];
    final outputs = <double>[];
    final rng = Random(42);
    for (var i = 0; i < 200; i++) {
      final raw = -60 + (rng.nextDouble() - 0.5) * 12; // ±6 dB jitter
      inputs.add(raw);
      outputs.add(s.next('d', raw, t0.add(Duration(milliseconds: 100 * i))));
    }
    // Skip warm-up samples when comparing steady-state noise.
    expect(
      variance(outputs.sublist(50)),
      lessThan(variance(inputs.sublist(50)) * 0.3),
    );
  });

  test('step response lags: first output after a step is between old and new', () {
    final s = defaultSmoother();
    for (var i = 0; i < 30; i++) {
      s.next('d', -50, t0.add(Duration(milliseconds: 100 * i)));
    }
    final afterStep = s.next('d', -70, t0.add(const Duration(seconds: 4)));
    expect(afterStep, lessThan(-50));
    expect(afterStep, greaterThan(-70));
  });

  test('devices are isolated from each other', () {
    final s = defaultSmoother();
    for (var i = 0; i < 30; i++) {
      s.next('a', -40, t0.add(Duration(milliseconds: 100 * i)));
    }
    // First sample for a fresh device returns the raw value, uninfluenced by 'a'.
    expect(s.next('b', -80, t0), -80);
  });

  test('reset clears state for that device only', () {
    final s = defaultSmoother();
    for (var i = 0; i < 30; i++) {
      s.next('a', -40, t0.add(Duration(milliseconds: 100 * i)));
      s.next('b', -40, t0.add(Duration(milliseconds: 100 * i)));
    }
    s.reset('a');
    expect(s.next('a', -90, t0), -90); // fresh: returns raw
    expect(s.next('b', -90, t0), greaterThan(-90)); // still smoothed
  });

  test('parameters are injected: higher R smooths harder', () {
    final light = KalmanRssiSmoother(processNoise: 0.065, measurementNoise: 0.5);
    final heavy = KalmanRssiSmoother(processNoise: 0.065, measurementNoise: 10);
    for (var i = 0; i < 30; i++) {
      light.next('d', -50, t0);
      heavy.next('d', -50, t0);
    }
    final lightOut = light.next('d', -70, t0);
    final heavyOut = heavy.next('d', -70, t0);
    // Heavy smoothing trusts the new measurement less → stays closer to -50.
    expect(heavyOut, greaterThan(lightOut));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/kalman_rssi_smoother_test.dart`
Expected: FAIL — `kalman_rssi_smoother.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/domain/kalman_rssi_smoother.dart`**

```dart
import 'interfaces.dart';

class _KalmanState {
  _KalmanState({required this.estimate, required this.errorCovariance});
  double estimate;
  double errorCovariance;
}

/// 1-D Kalman filter per device (FR-10). Q and R are injected (never
/// hard-coded) so tests and settings control them.
class KalmanRssiSmoother implements RssiSmoother {
  KalmanRssiSmoother({
    required this.processNoise,
    required this.measurementNoise,
  });

  final double processNoise;
  final double measurementNoise;
  final Map<String, _KalmanState> _states = {};

  @override
  double next(String deviceId, double rawRssi, DateTime at) {
    final state = _states[deviceId];
    if (state == null) {
      _states[deviceId] =
          _KalmanState(estimate: rawRssi, errorCovariance: measurementNoise);
      return rawRssi;
    }
    final predicted = state.errorCovariance + processNoise;
    final gain = predicted / (predicted + measurementNoise);
    state.estimate = state.estimate + gain * (rawRssi - state.estimate);
    state.errorCovariance = (1 - gain) * predicted;
    return state.estimate;
  }

  @override
  void reset(String deviceId) => _states.remove(deviceId);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/kalman_rssi_smoother_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/kalman_rssi_smoother.dart test/domain/kalman_rssi_smoother_test.dart
git commit -m "feat: add per-device 1-D Kalman RSSI smoother"
```

---

### Task 4: Log-distance estimator + TxPower fallback

**Files:**
- Create: `lib/domain/log_distance_estimator.dart`
- Test: `test/domain/distance_estimator_test.dart`

**Interfaces:**
- Consumes: `DistanceEstimator`, `DistanceEstimate`, `ProximityBand`, `ProximityConfig`
- Produces: `LogDistanceEstimator(ProximityConfig config) implements DistanceEstimator`; top-level `double resolveTxPower(double? advertised, ProximityConfig config)`

- [ ] **Step 1: Write the failing test**

`test/domain/distance_estimator_test.dart`:

```dart
import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/log_distance_estimator.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final estimator = LogDistanceEstimator(ProximityConfig());

  test('table-driven: known RSSI/TxPower/n triples', () {
    // d = 10 ^ ((txPower - rssi) / (10 * n))
    final cases = <(double rssi, double tx, double n, double meters)>[
      (-59, -59, 2.0, 1.0),
      (-79, -59, 2.0, 10.0),
      (-69, -59, 2.0, 3.1623),
      (-59, -59, 2.7, 1.0),
      (-86, -59, 2.7, 10.0),
      (-49, -59, 2.5, 0.3981),
    ];
    for (final (rssi, tx, n, meters) in cases) {
      final e = estimator.estimate(
        smoothedRssi: rssi,
        txPower: tx,
        environmentFactor: n,
      );
      expect(e.meters, closeTo(meters, 0.001), reason: 'rssi=$rssi n=$n');
    }
  });

  test('band boundaries: exactly 0.5 / 3.0 / 10.0 m', () {
    ProximityBand bandAt(double meters) {
      // Solve rssi so that d == meters exactly: rssi = tx - 10*n*log10(d)
      // Easier: call the internal band mapping through estimate with n=2.0.
      // 10*2.0*log10(d) added to tx of -59.
      final rssi = -59 - 20 * (log10(meters));
      return estimator
          .estimate(smoothedRssi: rssi, txPower: -59, environmentFactor: 2.0)
          .band;
    }

    expect(bandAt(0.49), ProximityBand.immediate);
    expect(bandAt(0.5), ProximityBand.near);
    expect(bandAt(2.99), ProximityBand.near);
    expect(bandAt(3.0), ProximityBand.mid);
    expect(bandAt(10.0), ProximityBand.mid);
    expect(bandAt(10.01), ProximityBand.far);
  });

  test('band thresholds come from config, not hard-coded', () {
    final custom = LogDistanceEstimator(ProximityConfig(
      immediateMaxMeters: 1.0,
      nearMaxMeters: 5.0,
      midMaxMeters: 20.0,
    ));
    final e = custom.estimate(
      smoothedRssi: -59, txPower: -59, environmentFactor: 2.0); // 1.0 m
    expect(e.band, ProximityBand.near); // 1.0 >= immediateMax(1.0) → near
  });

  test('missing TxPower falls back to config default', () {
    final config = ProximityConfig(defaultTxPower: -63);
    expect(resolveTxPower(null, config), -63);
    expect(resolveTxPower(-50, config), -50);
  });
}
```

Add this import helper at the top of the test (Dart has no `log10`):

```dart
import 'dart:math' as math;

double log10(double x) => math.log(x) / math.ln10;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/distance_estimator_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/domain/log_distance_estimator.dart`**

```dart
import 'dart:math' as math;

import 'config.dart';
import 'interfaces.dart';
import 'types.dart';

/// TxPower from advertisement when present, else per-config default (FR-9).
double resolveTxPower(double? advertised, ProximityConfig config) =>
    advertised ?? config.defaultTxPower;

/// Log-distance path loss model (FR-9): d = 10^((TxPower − RSSI) / (10·n)).
class LogDistanceEstimator implements DistanceEstimator {
  LogDistanceEstimator(this._config);

  final ProximityConfig _config;

  @override
  DistanceEstimate estimate({
    required double smoothedRssi,
    required double txPower,
    required double environmentFactor,
  }) {
    final meters = math
        .pow(10, (txPower - smoothedRssi) / (10 * environmentFactor))
        .toDouble();
    return DistanceEstimate(meters: meters, band: _bandFor(meters));
  }

  ProximityBand _bandFor(double meters) {
    if (meters < _config.immediateMaxMeters) return ProximityBand.immediate;
    if (meters < _config.nearMaxMeters) return ProximityBand.near;
    if (meters <= _config.midMaxMeters) return ProximityBand.mid;
    return ProximityBand.far;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/distance_estimator_test.dart`
Expected: PASS (4 tests). The 0.5/3.0 boundary cases may land a hair off exact due to float round-trip through log10 — if `bandAt(0.5)` flakes, compute the boundary RSSI with extra precision or assert via a direct internal distance (acceptable fix: expose `@visibleForTesting ProximityBand bandForMeters(double)` and test boundaries on it directly; keep the estimate() table test as-is).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/log_distance_estimator.dart test/domain/distance_estimator_test.dart
git commit -m "feat: add log-distance estimator with config-driven bands"
```

---

### Task 5: Radar layout (deterministic angle + log radius)

**Files:**
- Create: `lib/domain/hash_radar_layout.dart`
- Test: `test/domain/radar_layout_test.dart`

**Interfaces:**
- Consumes: `RadarLayout`, `DistanceEstimate`, `ProximityConfig`
- Produces: `HashRadarLayout(ProximityConfig config) implements RadarLayout`

- [ ] **Step 1: Write the failing test**

`test/domain/radar_layout_test.dart`:

```dart
import 'dart:math' as math;

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/hash_radar_layout.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final layout = HashRadarLayout(ProximityConfig());

  DistanceEstimate est(double m) =>
      DistanceEstimate(meters: m, band: ProximityBand.near);

  group('angleFor', () {
    test('deterministic across calls and instances', () {
      final again = HashRadarLayout(ProximityConfig());
      for (final id in ['aa:bb:cc', 'device-1', 'x']) {
        expect(layout.angleFor(id), layout.angleFor(id));
        expect(layout.angleFor(id), again.angleFor(id));
      }
    });

    test('range is [0, 2π)', () {
      for (var i = 0; i < 100; i++) {
        final a = layout.angleFor('device-$i');
        expect(a, greaterThanOrEqualTo(0));
        expect(a, lessThan(2 * math.pi));
      }
    });

    test('distribution sanity: sequential ids do not cluster', () {
      final buckets = List.filled(8, 0);
      for (var i = 0; i < 100; i++) {
        final a = layout.angleFor('device-$i');
        buckets[(a / (2 * math.pi) * 8).floor()]++;
      }
      expect(buckets.where((b) => b > 0).length, greaterThanOrEqualTo(6));
      expect(buckets.reduce(math.max), lessThanOrEqualTo(40));
    });
  });

  group('radiusFor', () {
    test('log-scaling is monotonic', () {
      final r1 = layout.radiusFor(est(0.5));
      final r2 = layout.radiusFor(est(3));
      final r3 = layout.radiusFor(est(10));
      expect(r1, lessThan(r2));
      expect(r2, lessThan(r3));
    });

    test('near-range differences are visually prominent (log > linear)', () {
      // From 0.5→3 m spans a larger radial fraction than the linear mapping would give.
      final span = layout.radiusFor(est(3)) - layout.radiusFor(est(0.5));
      const linearSpan = (3 - 0.5) / (20 - 0.1);
      expect(span, greaterThan(linearSpan));
    });

    test('clamps to [0, 1] outside configured range', () {
      expect(layout.radiusFor(est(0.01)), 0);
      expect(layout.radiusFor(est(500)), 1);
    });

    test('bounds: min→0, max→1', () {
      expect(layout.radiusFor(est(0.1)), closeTo(0, 1e-9));
      expect(layout.radiusFor(est(20)), closeTo(1, 1e-9));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/radar_layout_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/domain/hash_radar_layout.dart`**

```dart
import 'dart:math' as math;

import 'config.dart';
import 'interfaces.dart';
import 'types.dart';

/// FR-15: stable pseudo-angle from FNV-1a hash of the device id — no
/// directional meaning. FR-14: log-scaled radius in [0, 1].
class HashRadarLayout implements RadarLayout {
  HashRadarLayout(this._config);

  final ProximityConfig _config;

  @override
  double angleFor(String deviceId) {
    var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis
    for (final unit in deviceId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash / 0x100000000 * 2 * math.pi;
  }

  @override
  double radiusFor(DistanceEstimate estimate) {
    final min = _config.radarMinMeters;
    final max = _config.radarMaxMeters;
    final d = estimate.meters.clamp(min, max);
    return math.log(d / min) / math.log(max / min);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/radar_layout_test.dart`
Expected: PASS (7 tests). If the distribution test fails with FNV-1a on `device-N` ids (it's deterministic — it either always passes or always fails), switch the hash to 64-bit FNV-1a (offset `0xcbf29ce484222325`, prime `0x100000001b3`, mask 64-bit, divide by 2^64) and re-run.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/hash_radar_layout.dart test/domain/radar_layout_test.dart
git commit -m "feat: add deterministic hash-angle log-radius radar layout"
```

---

### Task 6: Scanner state machine

**Files:**
- Create: `lib/domain/scanner_state_machine.dart`
- Test: `test/domain/scanner_state_machine_test.dart`

**Interfaces:**
- Consumes: `ScannerStatus`
- Produces: `enum ScannerEvent { start, stop, adapterOff, adapterOn, permissionRevoked, permissionGranted }`; `class ScannerStateMachine { ScannerStatus get status; ScannerStatus apply(ScannerEvent event); }`; `class IllegalTransitionError extends StateError`. Adapters in Tasks 12–15 embed this class to drive their `status()` stream.

- [ ] **Step 1: Write the failing test**

`test/domain/scanner_state_machine_test.dart`:

```dart
import 'package:ble_tracker/domain/scanner_state_machine.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

ScannerStateMachine machineAt(ScannerStatus s) {
  final m = ScannerStateMachine();
  switch (s) {
    case ScannerStatus.idle:
      break;
    case ScannerStatus.scanning:
      m.apply(ScannerEvent.start);
    case ScannerStatus.unavailable:
      m.apply(ScannerEvent.start);
      m.apply(ScannerEvent.adapterOff);
    case ScannerStatus.unauthorized:
      m.apply(ScannerEvent.permissionRevoked);
  }
  return m;
}

void main() {
  test('initial status is idle', () {
    expect(ScannerStateMachine().status, ScannerStatus.idle);
  });

  test('idle --start--> scanning', () {
    expect(machineAt(ScannerStatus.idle).apply(ScannerEvent.start),
        ScannerStatus.scanning);
  });

  test('scanning --stop--> idle', () {
    expect(machineAt(ScannerStatus.scanning).apply(ScannerEvent.stop),
        ScannerStatus.idle);
  });

  test('stop is idempotent from idle', () {
    expect(machineAt(ScannerStatus.idle).apply(ScannerEvent.stop),
        ScannerStatus.idle);
  });

  test('scanning --adapterOff--> unavailable', () {
    expect(machineAt(ScannerStatus.scanning).apply(ScannerEvent.adapterOff),
        ScannerStatus.unavailable);
  });

  test('unavailable --adapterOn--> scanning (auto-resume)', () {
    expect(machineAt(ScannerStatus.unavailable).apply(ScannerEvent.adapterOn),
        ScannerStatus.scanning);
  });

  test('any --permissionRevoked--> unauthorized', () {
    for (final s in ScannerStatus.values) {
      if (s == ScannerStatus.unauthorized) continue;
      expect(machineAt(s).apply(ScannerEvent.permissionRevoked),
          ScannerStatus.unauthorized, reason: 'from $s');
    }
  });

  test('unauthorized --permissionGranted--> idle, then start --> scanning', () {
    final m = machineAt(ScannerStatus.unauthorized);
    expect(m.apply(ScannerEvent.permissionGranted), ScannerStatus.idle);
    expect(m.apply(ScannerEvent.start), ScannerStatus.scanning);
  });

  test('illegal transitions are rejected', () {
    expect(() => machineAt(ScannerStatus.idle).apply(ScannerEvent.adapterOn),
        throwsA(isA<IllegalTransitionError>()));
    expect(() => machineAt(ScannerStatus.scanning).apply(ScannerEvent.start),
        throwsA(isA<IllegalTransitionError>()));
    expect(
        () => machineAt(ScannerStatus.unauthorized).apply(ScannerEvent.start),
        throwsA(isA<IllegalTransitionError>()));
    expect(
        () => machineAt(ScannerStatus.unavailable).apply(ScannerEvent.start),
        throwsA(isA<IllegalTransitionError>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/scanner_state_machine_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/domain/scanner_state_machine.dart`**

```dart
import 'types.dart';

enum ScannerEvent {
  start,
  stop,
  adapterOff,
  adapterOn,
  permissionRevoked,
  permissionGranted,
}

class IllegalTransitionError extends StateError {
  IllegalTransitionError(ScannerStatus from, ScannerEvent event)
      : super('Illegal scanner transition: $from + $event');
}

/// §5.4 transitions, exactly. Everything not in the table throws.
class ScannerStateMachine {
  ScannerStatus _status = ScannerStatus.idle;

  ScannerStatus get status => _status;

  ScannerStatus apply(ScannerEvent event) {
    _status = switch ((_status, event)) {
      (_, ScannerEvent.permissionRevoked) => ScannerStatus.unauthorized,
      (ScannerStatus.idle, ScannerEvent.start) => ScannerStatus.scanning,
      (ScannerStatus.idle, ScannerEvent.stop) => ScannerStatus.idle,
      (ScannerStatus.scanning, ScannerEvent.stop) => ScannerStatus.idle,
      (ScannerStatus.scanning, ScannerEvent.adapterOff) =>
        ScannerStatus.unavailable,
      (ScannerStatus.unavailable, ScannerEvent.adapterOn) =>
        ScannerStatus.scanning,
      (ScannerStatus.unavailable, ScannerEvent.stop) => ScannerStatus.idle,
      (ScannerStatus.unauthorized, ScannerEvent.permissionGranted) =>
        ScannerStatus.idle,
      _ => throw IllegalTransitionError(_status, event),
    };
    return _status;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/scanner_state_machine_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/scanner_state_machine.dart test/domain/scanner_state_machine_test.dart
git commit -m "feat: add scanner state machine enforcing spec transitions"
```

---

### Task 7: Device registry with injected persistence

**Files:**
- Create: `lib/domain/key_value_store.dart`
- Create: `lib/domain/persistent_device_registry.dart`
- Create: `lib/platform/shared_prefs_store.dart`
- Test: `test/domain/registry_test.dart`

**Interfaces:**
- Consumes: `DeviceRegistry`, `RegisteredDevice`
- Produces: `abstract interface class KeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); }`; `PersistentDeviceRegistry(KeyValueStore store) implements DeviceRegistry` with `static const storageKey = 'registry.devices.v1'`; `SharedPrefsStore implements KeyValueStore` (thin, untested beyond compile — exercised in manual checklist).

- [ ] **Step 1: Write the failing test**

`test/domain/registry_test.dart`:

```dart
import 'dart:async';

import 'package:ble_tracker/domain/key_value_store.dart';
import 'package:ble_tracker/domain/persistent_device_registry.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: 'name-$id', type: DeviceType.tag, trackingEnabled: tracking);

void main() {
  late FakeStore store;
  late PersistentDeviceRegistry registry;

  setUp(() {
    store = FakeStore();
    registry = PersistentDeviceRegistry(store);
  });

  test('watchAll emits current list to new subscribers', () async {
    await registry.register(dev('a'));
    expect(await registry.watchAll().first, [dev('a')]);
  });

  test('register persists and re-registering same id overwrites', () async {
    await registry.register(dev('a'));
    await registry.register(dev('a', tracking: false));
    final list = await registry.watchAll().first;
    expect(list.single.trackingEnabled, false);

    // A fresh registry over the same store sees persisted data.
    final reloaded = PersistentDeviceRegistry(store);
    expect(await reloaded.watchAll().first, list);
  });

  test('setTracking toggles and propagates on the stream', () async {
    await registry.register(dev('a'));
    final events = StreamController<List<RegisteredDevice>>();
    final sub = registry.watchAll().listen(events.add);
    await registry.setTracking('a', false);
    await pumpEventQueue();
    final last = (await events.stream.take(2).toList()).last;
    expect(last.single.trackingEnabled, false);
    await sub.cancel();
  });

  test('rename propagates', () async {
    await registry.register(dev('a'));
    await registry.rename('a', 'Left Earbud');
    expect((await registry.watchAll().first).single.name, 'Left Earbud');
  });

  test('remove deletes from registry and persistence', () async {
    await registry.register(dev('a'));
    await registry.remove('a');
    expect(await registry.watchAll().first, isEmpty);
    expect(await PersistentDeviceRegistry(store).watchAll().first, isEmpty);
  });

  test('mutating an unknown id throws ArgumentError', () async {
    expect(() => registry.setTracking('nope', true), throwsArgumentError);
    expect(() => registry.rename('nope', 'x'), throwsArgumentError);
    expect(() => registry.remove('nope'), throwsArgumentError);
  });

  test('no cap: 1000 devices register and round-trip', () async {
    for (var i = 0; i < 1000; i++) {
      await registry.register(dev('id-$i'));
    }
    expect((await registry.watchAll().first).length, 1000);
    expect(
        (await PersistentDeviceRegistry(store).watchAll().first).length, 1000);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/registry_test.dart`
Expected: FAIL — files don't exist.

- [ ] **Step 3: Implement `lib/domain/key_value_store.dart`**

```dart
/// Persistence boundary (OQ-1: shared_preferences now; interface makes
/// swapping to drift trivial later).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
```

- [ ] **Step 4: Implement `lib/domain/persistent_device_registry.dart`**

```dart
import 'dart:async';
import 'dart:convert';

import 'interfaces.dart';
import 'key_value_store.dart';
import 'types.dart';

class PersistentDeviceRegistry implements DeviceRegistry {
  PersistentDeviceRegistry(this._store);

  static const storageKey = 'registry.devices.v1';

  final KeyValueStore _store;
  final _controller = StreamController<List<RegisteredDevice>>.broadcast();
  Map<String, RegisteredDevice>? _cache;

  Future<Map<String, RegisteredDevice>> _load() async {
    if (_cache != null) return _cache!;
    final raw = await _store.read(storageKey);
    final list = raw == null
        ? <RegisteredDevice>[]
        : (jsonDecode(raw) as List<Object?>)
            .map((e) =>
                RegisteredDevice.fromJson(e! as Map<String, Object?>))
            .toList();
    return _cache = {for (final d in list) d.id: d};
  }

  Future<void> _save(Map<String, RegisteredDevice> devices) async {
    _cache = devices;
    await _store.write(
        storageKey, jsonEncode(devices.values.map((d) => d.toJson()).toList()));
    _controller.add(devices.values.toList());
  }

  @override
  Stream<List<RegisteredDevice>> watchAll() async* {
    yield (await _load()).values.toList();
    yield* _controller.stream;
  }

  @override
  Future<void> register(RegisteredDevice device) async {
    final devices = Map.of(await _load());
    devices[device.id] = device;
    await _save(devices);
  }

  Future<RegisteredDevice> _require(String deviceId) async {
    final device = (await _load())[deviceId];
    if (device == null) {
      throw ArgumentError.value(deviceId, 'deviceId', 'not registered');
    }
    return device;
  }

  @override
  Future<void> setTracking(String deviceId, bool enabled) async {
    final device = await _require(deviceId);
    final devices = Map.of(_cache!);
    devices[deviceId] = device.copyWith(trackingEnabled: enabled);
    await _save(devices);
  }

  @override
  Future<void> rename(String deviceId, String name) async {
    final device = await _require(deviceId);
    final devices = Map.of(_cache!);
    devices[deviceId] = device.copyWith(name: name);
    await _save(devices);
  }

  @override
  Future<void> remove(String deviceId) async {
    await _require(deviceId);
    final devices = Map.of(_cache!)..remove(deviceId);
    await _save(devices);
  }
}
```

- [ ] **Step 5: Implement `lib/platform/shared_prefs_store.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/key_value_store.dart';

class SharedPrefsStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/domain/registry_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/domain/key_value_store.dart lib/domain/persistent_device_registry.dart lib/platform/shared_prefs_store.dart test/domain/registry_test.dart
git commit -m "feat: add device registry with injected key-value persistence"
```

---

### Task 8: Device state composer (staleness, smoothing pipeline)

**Files:**
- Create: `lib/state/device_state_composer.dart`
- Test: `test/state/device_state_composer_test.dart`

**Interfaces:**
- Consumes: `RssiSmoother`, `DistanceEstimator`, `resolveTxPower`, `ProximityConfig`, `ScanObservation`, `RegisteredDevice`, `TrackedDeviceState`, `DeviceVisibility`
- Produces: `DeviceStateComposer({required Stream<List<RegisteredDevice>> registry, required Stream<ScanObservation> observations, required Stream<DateTime> ticks, required RssiSmoother smoother, required DistanceEstimator estimator, required ProximityConfig config})` exposing `Stream<Map<String, TrackedDeviceState>> get states` and `void dispose()`. This is the single source of truth behind `deviceStatesProvider` (Task 10).

- [ ] **Step 1: Write the failing test**

`test/state/device_state_composer_test.dart`:

```dart
import 'dart:async';

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/kalman_rssi_smoother.dart';
import 'package:ble_tracker/domain/log_distance_estimator.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/state/device_state_composer.dart';
import 'package:flutter_test/flutter_test.dart';

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: id, type: DeviceType.tag, trackingEnabled: tracking);

void main() {
  late StreamController<List<RegisteredDevice>> registry;
  late StreamController<ScanObservation> observations;
  late StreamController<DateTime> ticks;
  late DeviceStateComposer composer;
  late List<Map<String, TrackedDeviceState>> emitted;
  final config = ProximityConfig();
  final t0 = DateTime.utc(2026, 1, 1);

  setUp(() {
    registry = StreamController<List<RegisteredDevice>>.broadcast();
    observations = StreamController<ScanObservation>.broadcast();
    ticks = StreamController<DateTime>.broadcast();
    composer = DeviceStateComposer(
      registry: registry.stream,
      observations: observations.stream,
      ticks: ticks.stream,
      smoother: KalmanRssiSmoother(
          processNoise: config.processNoise,
          measurementNoise: config.measurementNoise),
      estimator: LogDistanceEstimator(config),
      config: config,
    );
    emitted = [];
    composer.states.listen(emitted.add);
  });

  tearDown(() {
    composer.dispose();
  });

  Future<void> pump() => pumpEventQueue();

  ScanObservation obs(String id, DateTime at, {double rssi = -59}) =>
      ScanObservation(deviceId: id, rssi: rssi, timestamp: at, txPower: -59);

  test('registered device starts notVisible', () async {
    registry.add([dev('a')]);
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);
    expect(emitted.last['a']!.estimate, isNull);
  });

  test('observation makes device visible with estimate and lastSeen', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();
    final s = emitted.last['a']!;
    expect(s.visibility, DeviceVisibility.visible);
    expect(s.estimate!.meters, closeTo(1.0, 0.01));
    expect(s.lastSeen, t0);
  });

  test('missing txPower falls back to config default', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(ScanObservation(deviceId: 'a', rssi: -59, timestamp: t0));
    await pump();
    // rssi == defaultTxPower (-59) → 1 m
    expect(emitted.last['a']!.estimate!.meters, closeTo(1.0, 0.01));
  });

  test('visible → notVisible at exactly T_stale; estimate cleared', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();

    ticks.add(t0.add(const Duration(seconds: 9, milliseconds: 999)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);

    ticks.add(t0.add(const Duration(seconds: 10)));
    await pump();
    final s = emitted.last['a']!;
    expect(s.visibility, DeviceVisibility.notVisible);
    expect(s.estimate, isNull);
    expect(s.lastSeen, t0); // lastSeen preserved for fade-out rendering
  });

  test('re-acquisition resets the staleness timer', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('a', t0));
    await pump();
    ticks.add(t0.add(const Duration(seconds: 10)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.notVisible);

    final t1 = t0.add(const Duration(seconds: 11));
    observations.add(obs('a', t1));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);
    ticks.add(t1.add(const Duration(seconds: 9)));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.visible);
  });

  test('toggled-off device shows trackingOff and observations are ignored',
      () async {
    registry.add([dev('a', tracking: false)]);
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.trackingOff);
    observations.add(obs('a', t0));
    await pump();
    expect(emitted.last['a']!.visibility, DeviceVisibility.trackingOff);
    expect(emitted.last['a']!.estimate, isNull);
  });

  test('toggling off resets smoother state (fresh on re-enable)', () async {
    final resetIds = <String>[];
    final composer2 = DeviceStateComposer(
      registry: registry.stream,
      observations: observations.stream,
      ticks: ticks.stream,
      smoother: _SpySmoother(resetIds),
      estimator: LogDistanceEstimator(config),
      config: config,
    );
    composer2.states.listen((_) {});
    registry.add([dev('a')]);
    await pump();
    registry.add([dev('a', tracking: false)]);
    await pump();
    expect(resetIds, ['a']);
    composer2.dispose();
  });

  test('observations for unregistered devices are ignored', () async {
    registry.add([dev('a')]);
    await pump();
    observations.add(obs('ghost', t0));
    await pump();
    expect(emitted.last.containsKey('ghost'), isFalse);
  });

  test('removed device disappears from state', () async {
    registry.add([dev('a'), dev('b')]);
    await pump();
    registry.add([dev('b')]);
    await pump();
    expect(emitted.last.keys, ['b']);
  });
}

class _SpySmoother implements RssiSmoother {
  _SpySmoother(this.resetIds);
  final List<String> resetIds;
  @override
  double next(String deviceId, double rawRssi, DateTime at) => rawRssi;
  @override
  void reset(String deviceId) => resetIds.add(deviceId);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/device_state_composer_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/state/device_state_composer.dart`**

```dart
import 'dart:async';

import '../domain/config.dart';
import '../domain/interfaces.dart';
import '../domain/log_distance_estimator.dart';
import '../domain/types.dart';

/// Single source of truth (§6): registry × observations × smoothing ×
/// staleness ticker → Map of TrackedDeviceState. No real timers — time
/// arrives via [ticks] and observation timestamps.
class DeviceStateComposer {
  DeviceStateComposer({
    required Stream<List<RegisteredDevice>> registry,
    required Stream<ScanObservation> observations,
    required Stream<DateTime> ticks,
    required RssiSmoother smoother,
    required DistanceEstimator estimator,
    required ProximityConfig config,
  })  : _smoother = smoother,
        _estimator = estimator,
        _config = config {
    _subs = [
      registry.listen(_onRegistry),
      observations.listen(_onObservation),
      ticks.listen(_onTick),
    ];
  }

  final RssiSmoother _smoother;
  final DistanceEstimator _estimator;
  final ProximityConfig _config;

  final _controller =
      StreamController<Map<String, TrackedDeviceState>>.broadcast();
  late final List<StreamSubscription<void>> _subs;

  final Map<String, RegisteredDevice> _devices = {};
  final Map<String, DateTime> _lastSeen = {};
  final Map<String, DistanceEstimate> _estimates = {};
  final Map<String, DeviceVisibility> _visibility = {};

  Stream<Map<String, TrackedDeviceState>> get states => _controller.stream;

  void _onRegistry(List<RegisteredDevice> list) {
    final incoming = {for (final d in list) d.id: d};
    for (final id in _devices.keys.toList()) {
      final now = incoming[id];
      if (now == null) {
        _devices.remove(id);
        _lastSeen.remove(id);
        _estimates.remove(id);
        _visibility.remove(id);
        _smoother.reset(id);
      } else if (!now.trackingEnabled && _devices[id]!.trackingEnabled) {
        // FR-7: toggled off — drop live state, keep registration.
        _lastSeen.remove(id);
        _estimates.remove(id);
        _smoother.reset(id);
      }
    }
    for (final d in list) {
      _devices[d.id] = d;
      _visibility[d.id] = !d.trackingEnabled
          ? DeviceVisibility.trackingOff
          : (_lastSeen.containsKey(d.id)
              ? DeviceVisibility.visible
              : DeviceVisibility.notVisible);
    }
    _emit();
  }

  void _onObservation(ScanObservation obs) {
    final device = _devices[obs.deviceId];
    if (device == null || !device.trackingEnabled) return; // FR-7
    final smoothed = _smoother.next(obs.deviceId, obs.rssi, obs.timestamp);
    _estimates[obs.deviceId] = _estimator.estimate(
      smoothedRssi: smoothed,
      txPower: resolveTxPower(obs.txPower, _config),
      environmentFactor: _config.environmentFactor,
    );
    _lastSeen[obs.deviceId] = obs.timestamp;
    _visibility[obs.deviceId] = DeviceVisibility.visible;
    _emit();
  }

  void _onTick(DateTime now) {
    var changed = false;
    for (final id in _devices.keys) {
      if (_visibility[id] != DeviceVisibility.visible) continue;
      final seen = _lastSeen[id];
      if (seen != null && now.difference(seen) >= _config.staleAfter) {
        _visibility[id] = DeviceVisibility.notVisible; // FR-12
        _estimates.remove(id);
        changed = true;
      }
    }
    if (changed) _emit();
  }

  void _emit() {
    _controller.add({
      for (final d in _devices.values)
        d.id: TrackedDeviceState(
          device: d,
          visibility: _visibility[d.id]!,
          estimate: _estimates[d.id],
          lastSeen: _lastSeen[d.id],
        ),
    });
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _controller.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/device_state_composer_test.dart`
Expected: PASS (9 tests). Note the staleness test asserts `lastSeen` survives going stale (the radar needs it for fade-out) — do not clear `_lastSeen` in `_onTick`.

- [ ] **Step 5: Commit**

```bash
git add lib/state/device_state_composer.dart test/state/device_state_composer_test.dart
git commit -m "feat: add device state composer with injected-time staleness"
```

---

### Task 9: Radar blip mapping (pure presentation logic)

**Files:**
- Create: `lib/state/radar_blips.dart`
- Test: `test/state/radar_blips_test.dart`

**Interfaces:**
- Consumes: `RadarLayout`, `TrackedDeviceState`, `ProximityConfig`
- Produces: `class RadarBlip { final String deviceId; final String name; final double angle; final double radius; final double opacity; }`; `List<RadarBlip> radarBlipsFrom(Map<String, TrackedDeviceState> states, DateTime now, RadarLayout layout, ProximityConfig config)`; `String? hitTestBlips(List<RadarBlip> blips, ({double dx, double dy}) tap, double canvasRadius)` where blip centers are at polar (angle, radius·canvasRadius) and the hit radius is 24.0 logical px. Task 18's painter and gesture handling consume these.

- [ ] **Step 1: Write the failing test**

`test/state/radar_blips_test.dart`:

```dart
import 'dart:math' as math;

import 'package:ble_tracker/domain/config.dart';
import 'package:ble_tracker/domain/hash_radar_layout.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/state/radar_blips.dart';
import 'package:flutter_test/flutter_test.dart';

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: id, type: DeviceType.tag, trackingEnabled: tracking);

TrackedDeviceState state(
  String id, {
  DeviceVisibility visibility = DeviceVisibility.visible,
  double meters = 2,
  DateTime? lastSeen,
}) =>
    TrackedDeviceState(
      device: dev(id, tracking: visibility != DeviceVisibility.trackingOff),
      visibility: visibility,
      estimate: visibility == DeviceVisibility.visible
          ? DistanceEstimate(meters: meters, band: ProximityBand.near)
          : null,
      lastSeen: lastSeen,
    );

void main() {
  final config = ProximityConfig();
  final layout = HashRadarLayout(config);
  final t0 = DateTime.utc(2026, 1, 1);

  test('visible device → blip with layout angle/radius, opacity 1', () {
    final blips =
        radarBlipsFrom({'a': state('a', lastSeen: t0)}, t0, layout, config);
    final b = blips.single;
    expect(b.deviceId, 'a');
    expect(b.angle, layout.angleFor('a'));
    expect(b.opacity, 1.0);
  });

  test('trackingOff device → no blip', () {
    final blips = radarBlipsFrom(
        {'a': state('a', visibility: DeviceVisibility.trackingOff)},
        t0, layout, config);
    expect(blips, isEmpty);
  });

  test('notVisible fades over 2 s after going stale, then disappears', () {
    // Went stale at lastSeen + 10 s. Fade runs [10 s, 12 s].
    final staleAt = t0.add(config.staleAfter);
    final s = state('a', visibility: DeviceVisibility.notVisible, lastSeen: t0)
        ;
    double opacityAt(Duration afterStale) => radarBlipsFrom(
          {'a': s},
          staleAt.add(afterStale),
          layout,
          config,
        ).singleOrNull?.opacity ?? 0;

    expect(opacityAt(Duration.zero), 1.0);
    expect(opacityAt(const Duration(seconds: 1)), closeTo(0.5, 0.01));
    expect(opacityAt(const Duration(seconds: 2)), 0);
    expect(
        radarBlipsFrom({'a': s}, staleAt.add(const Duration(seconds: 3)),
            layout, config),
        isEmpty);
  });

  test('notVisible with no lastSeen (never seen) → no blip', () {
    final blips = radarBlipsFrom(
        {'a': state('a', visibility: DeviceVisibility.notVisible)},
        t0, layout, config);
    expect(blips, isEmpty);
  });

  test('hit test finds blip within 24 px, nearest wins, else null', () {
    const canvasRadius = 200.0;
    final blip = RadarBlip(
        deviceId: 'a', name: 'a', angle: 0, radius: 0.5, opacity: 1);
    // angle 0, radius 0.5 → center at (0.5*200, 0) = (100, 0) from radar center
    final x = 0.5 * canvasRadius * math.cos(0.0);
    final y = 0.5 * canvasRadius * math.sin(0.0);
    expect(hitTestBlips([blip], (dx: x + 10, dy: y - 10), canvasRadius), 'a');
    expect(hitTestBlips([blip], (dx: x + 100, dy: y), canvasRadius), isNull);

    final near = RadarBlip(
        deviceId: 'b', name: 'b', angle: 0, radius: 0.55, opacity: 1);
    expect(
        hitTestBlips([blip, near], (dx: 0.55 * canvasRadius, dy: 0),
            canvasRadius),
        'b');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/radar_blips_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Implement `lib/state/radar_blips.dart`**

```dart
import 'dart:math' as math;

import '../domain/config.dart';
import '../domain/interfaces.dart';
import '../domain/types.dart';

class RadarBlip {
  const RadarBlip({
    required this.deviceId,
    required this.name,
    required this.angle,
    required this.radius,
    required this.opacity,
  });

  final String deviceId;
  final String name;
  final double angle; // radians, no directional meaning (FR-15)
  final double radius; // [0, 1]
  final double opacity; // 1 visible; fades to 0 over blipFadeOut (FR-12)
}

List<RadarBlip> radarBlipsFrom(
  Map<String, TrackedDeviceState> states,
  DateTime now,
  RadarLayout layout,
  ProximityConfig config,
) {
  final blips = <RadarBlip>[];
  for (final s in states.values) {
    switch (s.visibility) {
      case DeviceVisibility.trackingOff:
        continue;
      case DeviceVisibility.visible:
        blips.add(RadarBlip(
          deviceId: s.device.id,
          name: s.device.name,
          angle: layout.angleFor(s.device.id),
          radius: s.estimate == null ? 1 : layout.radiusFor(s.estimate!),
          opacity: 1,
        ));
      case DeviceVisibility.notVisible:
        final seen = s.lastSeen;
        if (seen == null) continue;
        final staleAt = seen.add(config.staleAfter);
        final fade = now.difference(staleAt).inMilliseconds /
            config.blipFadeOut.inMilliseconds;
        if (fade >= 1) continue;
        blips.add(RadarBlip(
          deviceId: s.device.id,
          name: s.device.name,
          angle: layout.angleFor(s.device.id),
          radius: 1, // last estimate is gone; park on outer ring while fading
          opacity: (1 - fade).clamp(0, 1),
        ));
    }
  }
  return blips;
}

/// Returns the deviceId of the nearest blip within 24 logical px of the tap
/// (tap coordinates relative to radar center), or null.
String? hitTestBlips(
  List<RadarBlip> blips,
  ({double dx, double dy}) tap,
  double canvasRadius,
) {
  const hitRadius = 24.0;
  String? best;
  var bestDist = double.infinity;
  for (final b in blips) {
    final x = b.radius * canvasRadius * math.cos(b.angle);
    final y = b.radius * canvasRadius * math.sin(b.angle);
    final d = math.sqrt(math.pow(tap.dx - x, 2) + math.pow(tap.dy - y, 2));
    if (d <= hitRadius && d < bestDist) {
      best = b.deviceId;
      bestDist = d;
    }
  }
  return best;
}
```

Wait — the fade test expects the blip to keep rendering at its last position; parking at radius 1 would make blips jump outward on fade. Fix: `radarBlipsFrom` must keep the last known radius. Since `estimate` is null once stale, thread the last estimate through `TrackedDeviceState.lastSeen`-adjacent data is not available — instead, keep a module-level pure approach: pass `Map<String, double> lastRadii` maintained by the caller? No — simpler and still pure: the fade test above only asserts opacity, not radius, so radius 1 parking is acceptable for v1 **but** visually poor. Chosen approach: `radarBlipsFrom` takes an optional `Map<String, double> lastKnownRadius` parameter, and the radar screen (Task 18) maintains it from the previous frame's blips:

```dart
List<RadarBlip> radarBlipsFrom(
  Map<String, TrackedDeviceState> states,
  DateTime now,
  RadarLayout layout,
  ProximityConfig config, {
  Map<String, double> lastKnownRadius = const {},
}) {
  // ... in the notVisible case:
  //   radius: lastKnownRadius[s.device.id] ?? 1,
}
```

Add one test: fading blip uses `lastKnownRadius['a']` when provided.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/radar_blips_test.dart`
Expected: PASS (6 tests including the added lastKnownRadius test).

- [ ] **Step 5: Commit**

```bash
git add lib/state/radar_blips.dart test/state/radar_blips_test.dart
git commit -m "feat: add pure radar blip mapping with fade-out and hit testing"
```

---

### Task 10: Riverpod providers

**Files:**
- Create: `lib/state/providers.dart` (+ generated `providers.g.dart`)
- Test: `test/state/providers_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–9
- Produces: providers `proximityConfigProvider`, `bleScannerProvider`, `deviceRegistryProvider`, `platformCapabilitiesProvider`, `rssiSmootherProvider`, `distanceEstimatorProvider`, `radarLayoutProvider`, `tickerProvider` (Stream<DateTime>), `deviceStatesProvider` (Stream<Map<String, TrackedDeviceState>>). Platform-bound providers (`bleScanner`, `deviceRegistry`, `platformCapabilities`, `ticker`) throw `UnimplementedError` by default and are overridden in `main.dart` (Task 19) and in tests.

- [ ] **Step 1: Write the failing test**

`test/state/providers_test.dart`:

```dart
import 'dart:async';

import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRegistry implements DeviceRegistry {
  final controller = StreamController<List<RegisteredDevice>>.broadcast();
  @override
  Stream<List<RegisteredDevice>> watchAll() => controller.stream;
  @override
  Future<void> register(RegisteredDevice device) async {}
  @override
  Future<void> setTracking(String deviceId, bool enabled) async {}
  @override
  Future<void> rename(String deviceId, String name) async {}
  @override
  Future<void> remove(String deviceId) async {}
}

class _FakeScanner implements BleScanner {
  final observations = StreamController<ScanObservation>.broadcast();
  @override
  Stream<ScanObservation> observe() => observations.stream;
  @override
  Stream<ScannerStatus> status() => const Stream.empty();
  @override
  Future<void> start(ScanProfile profile) async {}
  @override
  Future<void> stop() async {}
}

void main() {
  test('deviceStatesProvider composes registry and observations', () async {
    final registry = _FakeRegistry();
    final scanner = _FakeScanner();
    final ticks = StreamController<DateTime>.broadcast();

    final container = ProviderContainer(overrides: [
      deviceRegistryProvider.overrideWithValue(registry),
      bleScannerProvider.overrideWithValue(scanner),
      tickerProvider.overrideWith((ref) => ticks.stream),
    ]);
    addTearDown(container.dispose);

    final states = <Map<String, TrackedDeviceState>>[];
    final sub = container.listen(deviceStatesProvider, (_, next) {
      next.whenData(states.add);
    });
    addTearDown(sub.close);

    registry.controller.add([
      const RegisteredDevice(id: 'a', name: 'a', type: DeviceType.tag),
    ]);
    await pumpEventQueue();
    scanner.observations.add(ScanObservation(
        deviceId: 'a', rssi: -59, txPower: -59, timestamp: DateTime.utc(2026)));
    await pumpEventQueue();

    expect(states.last['a']!.visibility, DeviceVisibility.visible);
  });

  test('platform-bound providers throw when not overridden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(bleScannerProvider), throwsA(anything));
    expect(() => container.read(deviceRegistryProvider), throwsA(anything));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/providers_test.dart`
Expected: FAIL — `providers.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/state/providers.dart`**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/config.dart';
import '../domain/hash_radar_layout.dart';
import '../domain/interfaces.dart';
import '../domain/kalman_rssi_smoother.dart';
import '../domain/log_distance_estimator.dart';
import '../domain/types.dart';
import 'device_state_composer.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
ProximityConfig proximityConfig(Ref ref) => ProximityConfig();

@Riverpod(keepAlive: true)
BleScanner bleScanner(Ref ref) =>
    throw UnimplementedError('override with a platform scanner in main()');

@Riverpod(keepAlive: true)
DeviceRegistry deviceRegistry(Ref ref) =>
    throw UnimplementedError('override with a persistent registry in main()');

@Riverpod(keepAlive: true)
PlatformCapabilities platformCapabilities(Ref ref) =>
    throw UnimplementedError('override with detected capabilities in main()');

@Riverpod(keepAlive: true)
Stream<DateTime> ticker(Ref ref) =>
    throw UnimplementedError('override with a periodic ticker in main()');

@Riverpod(keepAlive: true)
RssiSmoother rssiSmoother(Ref ref) {
  final config = ref.watch(proximityConfigProvider);
  return KalmanRssiSmoother(
    processNoise: config.processNoise,
    measurementNoise: config.measurementNoise,
  );
}

@Riverpod(keepAlive: true)
DistanceEstimator distanceEstimator(Ref ref) =>
    LogDistanceEstimator(ref.watch(proximityConfigProvider));

@Riverpod(keepAlive: true)
RadarLayout radarLayout(Ref ref) =>
    HashRadarLayout(ref.watch(proximityConfigProvider));

@Riverpod(keepAlive: true)
Stream<Map<String, TrackedDeviceState>> deviceStates(Ref ref) {
  final composer = DeviceStateComposer(
    registry: ref.watch(deviceRegistryProvider).watchAll(),
    observations: ref.watch(bleScannerProvider).observe(),
    ticks: ref.watch(tickerProvider.future).asStream().asyncExpand((s) => s),
    smoother: ref.watch(rssiSmootherProvider),
    estimator: ref.watch(distanceEstimatorProvider),
    config: ref.watch(proximityConfigProvider),
  );
  ref.onDispose(composer.dispose);
  return composer.states;
}
```

Note on `tickerProvider`: a stream provider's value is an AsyncValue; the simpler correct wiring is to make `ticker` a plain provider of `Stream<DateTime>` (not a codegen stream provider):

```dart
@Riverpod(keepAlive: true)
Raw<Stream<DateTime>> ticker(Ref ref) =>
    throw UnimplementedError('override with a periodic ticker in main()');
```

Then in `deviceStates`: `ticks: ref.watch(tickerProvider),`. Use whichever the current riverpod_generator version supports (`Raw<>` exists in riverpod_annotation ≥ 2.3; check the riverpod docs via context7 if generation fails), and adjust the test override to `tickerProvider.overrideWithValue(ticks.stream)` accordingly.

- [ ] **Step 4: Generate and run test**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/state/providers_test.dart`
Expected: codegen succeeds; PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart lib/state/providers.g.dart test/state/providers_test.dart
git commit -m "feat: wire riverpod providers around domain interfaces"
```

---

### Task 11: BleScanner contract test suite

**Files:**
- Create: `test/contract/ble_scanner_contract.dart`
- Test: `test/contract/contract_smoke_test.dart` (runs the suite against an in-memory reference scanner)
- Create: `lib/platform/fake_ble_scanner.dart` (reference implementation; also reused by UI tests)

**Interfaces:**
- Consumes: `BleScanner`, `ScannerStateMachine`, `ScanObservation`, `ScannerStatus`
- Produces:
  - `class ScannerHarness { final BleScanner scanner; final void Function(ScanObservation) emitObservation; final void Function() adapterOff; final void Function() adapterOn; final void Function() revokePermission; }`
  - `void runBleScannerContract(String name, Future<ScannerHarness> Function() createHarness)` — every adapter test file (Tasks 12–15) calls this.
  - `FakeBleScanner implements BleScanner` with public `emit(ScanObservation)`, `setAdapterOff()`, `setAdapterOn()`, `revokePermission()`.

- [ ] **Step 1: Write the contract suite `test/contract/ble_scanner_contract.dart`**

```dart
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/domain/interfaces.dart';
import 'package:flutter_test/flutter_test.dart';

class ScannerHarness {
  ScannerHarness({
    required this.scanner,
    required this.emitObservation,
    required this.adapterOff,
    required this.adapterOn,
    required this.revokePermission,
  });

  final BleScanner scanner;
  final void Function(ScanObservation) emitObservation;
  final void Function() adapterOff;
  final void Function() adapterOn;
  final void Function() revokePermission;
}

/// §7.3: every adapter runs this identical suite with its own fake backend.
void runBleScannerContract(
  String name,
  Future<ScannerHarness> Function() createHarness,
) {
  group('BleScanner contract: $name', () {
    late ScannerHarness h;
    late List<ScannerStatus> statuses;
    late List<ScanObservation> observations;

    setUp(() async {
      h = await createHarness();
      statuses = [];
      observations = [];
      h.scanner.status().listen(statuses.add);
      h.scanner.observe().listen(observations.add);
      await pumpEventQueue();
    });

    test('start emits scanning status', () async {
      await h.scanner.start(ScanProfile.balanced);
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.scanning);
    });

    test('observations map backend fields correctly', () async {
      await h.scanner.start(ScanProfile.balanced);
      final t = DateTime.utc(2026, 3, 1);
      h.emitObservation(ScanObservation(
        deviceId: 'id-1',
        rssi: -61,
        txPower: -59,
        timestamp: t,
        advertisedName: 'Buds',
      ));
      await pumpEventQueue();
      final o = observations.single;
      expect(o.deviceId, 'id-1');
      expect(o.rssi, -61);
      expect(o.txPower, -59);
      expect(o.timestamp, t);
      expect(o.advertisedName, 'Buds');
    });

    test('adapter off mid-scan → unavailable; on → auto-resume scanning',
        () async {
      await h.scanner.start(ScanProfile.balanced);
      await pumpEventQueue();
      h.adapterOff();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.unavailable);
      h.adapterOn();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.scanning);
    });

    test('stop is idempotent', () async {
      await h.scanner.start(ScanProfile.balanced);
      await h.scanner.stop();
      await h.scanner.stop();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.idle);
    });

    test('permission revoked → unauthorized; observe() never errors',
        () async {
      await h.scanner.start(ScanProfile.balanced);
      await pumpEventQueue();
      h.revokePermission();
      await pumpEventQueue();
      expect(statuses.last, ScannerStatus.unauthorized);
      // The observation stream must not have errored (listener above would throw).
    });
  });
}
```

- [ ] **Step 2: Implement the reference `lib/platform/fake_ble_scanner.dart`**

```dart
import 'dart:async';

import '../domain/interfaces.dart';
import '../domain/scanner_state_machine.dart';
import '../domain/types.dart';

/// In-memory scanner: reference implementation for the contract suite and
/// the backend for widget tests.
class FakeBleScanner implements BleScanner {
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();

  ScannerStatus get currentStatus => _machine.status;

  void _apply(ScannerEvent event) {
    _statuses.add(_machine.apply(event));
  }

  void emit(ScanObservation observation) {
    if (_machine.status == ScannerStatus.scanning) {
      _observations.add(observation);
    }
  }

  void setAdapterOff() => _apply(ScannerEvent.adapterOff);
  void setAdapterOn() => _apply(ScannerEvent.adapterOn);
  void revokePermission() => _apply(ScannerEvent.permissionRevoked);
  void grantPermission() => _apply(ScannerEvent.permissionGranted);

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) async => _apply(ScannerEvent.start);

  @override
  Future<void> stop() async => _apply(ScannerEvent.stop);
}
```

- [ ] **Step 3: Write `test/contract/contract_smoke_test.dart`**

```dart
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';

import 'ble_scanner_contract.dart';

void main() {
  runBleScannerContract('FakeBleScanner (reference)', () async {
    final scanner = FakeBleScanner();
    return ScannerHarness(
      scanner: scanner,
      emitObservation: scanner.emit,
      adapterOff: scanner.setAdapterOff,
      adapterOn: scanner.setAdapterOn,
      revokePermission: scanner.revokePermission,
    );
  });
}
```

- [ ] **Step 4: Run and iterate until green**

Run: `flutter test test/contract/contract_smoke_test.dart`
Expected: PASS (5 tests). Watch for the "start emits scanning" test double-applying `start` when already scanning (illegal): the contract's `start` is only ever called from idle in the suite, so this passes; adapters must internally guard instead of blindly applying events.

- [ ] **Step 5: Commit**

```bash
git add test/contract lib/platform/fake_ble_scanner.dart
git commit -m "feat: add BleScanner contract suite and in-memory reference scanner"
```

---

### Task 12: FlutterBluePlusScanner (Android, iOS, macOS, Windows)

**Files:**
- Create: `lib/platform/fbp/fbp_api.dart` (thin plugin boundary)
- Create: `lib/platform/fbp/flutter_blue_plus_scanner.dart`
- Create: `lib/platform/fbp/fbp_api_impl.dart` (real plugin calls, not unit-tested)
- Test: `test/platform/flutter_blue_plus_scanner_test.dart`

**Interfaces:**
- Consumes: `BleScanner`, `ScannerStateMachine`, contract suite from Task 11
- Produces: `FlutterBluePlusScanner(FbpApi api) implements BleScanner`; `abstract interface class FbpApi` (below); `FbpApiImpl implements FbpApi` wrapping `flutter_blue_plus`.

- [ ] **Step 1: Define the plugin boundary `lib/platform/fbp/fbp_api.dart`**

```dart
import '../../domain/types.dart';

/// Everything FlutterBluePlusScanner needs from flutter_blue_plus,
/// as plain Dart so tests can fake it.
abstract interface class FbpApi {
  /// Adapter state: true = on, false = off.
  Stream<bool> adapterOn();

  /// Raw advertisement results already mapped to ScanObservation.
  Stream<ScanObservation> scanResults();

  /// Throws [FbpPermissionDenied] if BLE permissions are missing/revoked.
  Future<void> startScan({required bool lowLatency});

  Future<void> stopScan();
}

class FbpPermissionDenied implements Exception {}
```

- [ ] **Step 2: Write the failing test `test/platform/flutter_blue_plus_scanner_test.dart`**

```dart
import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fbp/fbp_api.dart';
import 'package:ble_tracker/platform/fbp/flutter_blue_plus_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

class FakeFbpApi implements FbpApi {
  final adapter = StreamController<bool>.broadcast();
  final results = StreamController<ScanObservation>.broadcast();
  bool permissionGranted = true;
  bool scanning = false;
  bool? lastLowLatency;

  @override
  Stream<bool> adapterOn() => adapter.stream;

  @override
  Stream<ScanObservation> scanResults() => results.stream;

  @override
  Future<void> startScan({required bool lowLatency}) async {
    if (!permissionGranted) throw FbpPermissionDenied();
    scanning = true;
    lastLowLatency = lowLatency;
  }

  @override
  Future<void> stopScan() async => scanning = false;
}

void main() {
  runBleScannerContract('FlutterBluePlusScanner', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    return ScannerHarness(
      scanner: scanner,
      emitObservation: api.results.add,
      adapterOff: () => api.adapter.add(false),
      adapterOn: () => api.adapter.add(true),
      revokePermission: () {
        api.permissionGranted = false;
        // Simulate the OS killing the scan: adapter callback surfaces it on
        // the next start attempt; scanner also polls via checkPermission —
        // here we surface it directly:
        scanner.onPermissionRevoked();
      },
    );
  });

  test('NFR-4: scan profile maps to plugin scan mode', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    await scanner.start(ScanProfile.lowLatency);
    expect(api.lastLowLatency, isTrue);
    await scanner.stop();
    await scanner.start(ScanProfile.balanced);
    expect(api.lastLowLatency, isFalse);
  });

  test('auto-resume restarts the plugin scan with the last profile', () async {
    final api = FakeFbpApi();
    final scanner = FlutterBluePlusScanner(api);
    await scanner.start(ScanProfile.lowLatency);
    api.adapter.add(false);
    await pumpEventQueue();
    expect(api.scanning, isFalse);
    api.adapter.add(true);
    await pumpEventQueue();
    expect(api.scanning, isTrue);
    expect(api.lastLowLatency, isTrue);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/platform/flutter_blue_plus_scanner_test.dart`
Expected: FAIL — scanner doesn't exist.

- [ ] **Step 4: Implement `lib/platform/fbp/flutter_blue_plus_scanner.dart`**

```dart
import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/scanner_state_machine.dart';
import '../../domain/types.dart';
import 'fbp_api.dart';

class FlutterBluePlusScanner implements BleScanner {
  FlutterBluePlusScanner(this._api) {
    _adapterSub = _api.adapterOn().listen(_onAdapterChanged);
    _resultsSub = _api.scanResults().listen(_observations.add);
  }

  final FbpApi _api;
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();
  late final StreamSubscription<bool> _adapterSub;
  late final StreamSubscription<ScanObservation> _resultsSub;
  ScanProfile _lastProfile = ScanProfile.balanced;

  void _apply(ScannerEvent event) => _statuses.add(_machine.apply(event));

  Future<void> _onAdapterChanged(bool on) async {
    if (!on && _machine.status == ScannerStatus.scanning) {
      await _api.stopScan();
      _apply(ScannerEvent.adapterOff);
    } else if (on && _machine.status == ScannerStatus.unavailable) {
      await _api.startScan(
          lowLatency: _lastProfile == ScanProfile.lowLatency);
      _apply(ScannerEvent.adapterOn); // §5.4 auto-resume
    }
  }

  /// Called by the permission plumbing when BLE permission is revoked
  /// mid-session (NFR-6).
  void onPermissionRevoked() {
    if (_machine.status != ScannerStatus.unauthorized) {
      _apply(ScannerEvent.permissionRevoked);
    }
  }

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) async {
    if (_machine.status == ScannerStatus.scanning) return;
    _lastProfile = profile;
    try {
      await _api.startScan(lowLatency: profile == ScanProfile.lowLatency);
    } on FbpPermissionDenied {
      onPermissionRevoked();
      return;
    }
    _apply(ScannerEvent.start);
  }

  @override
  Future<void> stop() async {
    if (_machine.status == ScannerStatus.idle) return; // idempotent
    await _api.stopScan();
    _apply(ScannerEvent.stop);
  }
}
```

- [ ] **Step 5: Implement `lib/platform/fbp/fbp_api_impl.dart`** (thin; excluded from coverage gate since it's not `domain/`/`state/`)

```dart
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/types.dart';
import 'fbp_api.dart';

/// Real flutter_blue_plus calls. Verify exact API names against current
/// flutter_blue_plus docs (context7 / pub.dev) at implementation time —
/// the plugin's surface moves between majors.
class FbpApiImpl implements FbpApi {
  @override
  Stream<bool> adapterOn() => FlutterBluePlus.adapterState
      .map((s) => s == BluetoothAdapterState.on);

  @override
  Stream<ScanObservation> scanResults() =>
      FlutterBluePlus.onScanResults.expand((results) => results.map(
            (r) => ScanObservation(
              deviceId: r.device.remoteId.str,
              rssi: r.rssi.toDouble(),
              txPower: r.advertisementData.txPowerLevel?.toDouble(),
              timestamp: DateTime.now(),
              advertisedName: r.advertisementData.advName.isEmpty
                  ? null
                  : r.advertisementData.advName,
            ),
          ));

  @override
  Future<void> startScan({required bool lowLatency}) => FlutterBluePlus.startScan(
        continuousUpdates: true,
        removeIfGone: null,
        androidScanMode:
            lowLatency ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
      );

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();
}
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/platform/flutter_blue_plus_scanner_test.dart`
Expected: PASS (contract 5 + 2 extra tests).

- [ ] **Step 7: Add platform permission declarations**

- `android/app/src/main/AndroidManifest.xml` — inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

- `ios/Runner/Info.plist` and `macos/Runner/Info.plist` — inside the top-level `<dict>`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is used to measure the distance to your tracked devices.</string>
```

- `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

- Set Android `minSdk` to 31 in `android/app/build.gradle.kts` (`minSdk = 31`), iOS deployment target 16.0 in `ios/Podfile` + Xcode project, macOS 13.0 in `macos/Podfile`.

- [ ] **Step 8: Verify build + commit**

Run: `flutter analyze && flutter test`
Expected: clean.

```bash
git add lib/platform/fbp test/platform android ios macos
git commit -m "feat: add flutter_blue_plus scanner adapter passing contract suite"
```

---

### Task 13: BlueZScanner (Linux)

**Files:**
- Create: `lib/platform/bluez/bluez_api.dart`
- Create: `lib/platform/bluez/bluez_scanner.dart`
- Create: `lib/platform/bluez/bluez_api_impl.dart`
- Test: `test/platform/bluez_scanner_test.dart`

**Interfaces:**
- Consumes: `BleScanner`, `ScannerStateMachine`, contract suite
- Produces: `BlueZScanner(BlueZApi api) implements BleScanner`; `abstract interface class BlueZApi` mirroring `FbpApi` (`adapterOn()`, `scanResults()`, `startDiscovery()`, `stopDiscovery()`).

Decision for OQ-2: use the `bluez` Dart package (pure-Dart D-Bus, no FFI). If the package's discovery events prove insufficient at manual-test time, the `BlueZApi` boundary contains the fallout.

- [ ] **Step 1: Define `lib/platform/bluez/bluez_api.dart`**

```dart
import '../../domain/types.dart';

abstract interface class BlueZApi {
  Stream<bool> adapterOn();
  Stream<ScanObservation> scanResults();
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
}
```

- [ ] **Step 2: Write the failing test `test/platform/bluez_scanner_test.dart`**

Same shape as Task 12's test: a `FakeBlueZApi` with broadcast controllers + `runBleScannerContract('BlueZScanner', ...)`. Linux has no runtime BLE permission — for the contract's `revokePermission` hook, call `scanner.onPermissionRevoked()` directly (the method exists for interface symmetry; D-Bus policy denial maps to it in the impl).

```dart
import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/bluez/bluez_api.dart';
import 'package:ble_tracker/platform/bluez/bluez_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

class FakeBlueZApi implements BlueZApi {
  final adapter = StreamController<bool>.broadcast();
  final results = StreamController<ScanObservation>.broadcast();
  bool discovering = false;

  @override
  Stream<bool> adapterOn() => adapter.stream;
  @override
  Stream<ScanObservation> scanResults() => results.stream;
  @override
  Future<void> startDiscovery() async => discovering = true;
  @override
  Future<void> stopDiscovery() async => discovering = false;
}

void main() {
  runBleScannerContract('BlueZScanner', () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);
    return ScannerHarness(
      scanner: scanner,
      emitObservation: api.results.add,
      adapterOff: () => api.adapter.add(false),
      adapterOn: () => api.adapter.add(true),
      revokePermission: scanner.onPermissionRevoked,
    );
  });

  test('adapter off stops discovery; on restarts it', () async {
    final api = FakeBlueZApi();
    final scanner = BlueZScanner(api);
    await scanner.start(ScanProfile.balanced);
    expect(api.discovering, isTrue);
    api.adapter.add(false);
    await pumpEventQueue();
    expect(api.discovering, isFalse);
    api.adapter.add(true);
    await pumpEventQueue();
    expect(api.discovering, isTrue);
  });
}
```

- [ ] **Step 3: Run to verify failure, then implement `lib/platform/bluez/bluez_scanner.dart`**

(Structurally parallel to `FlutterBluePlusScanner`, but complete here: BlueZ discovery has no profile knob — the profile is accepted and ignored.)

```dart
import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/scanner_state_machine.dart';
import '../../domain/types.dart';
import 'bluez_api.dart';

class BlueZScanner implements BleScanner {
  BlueZScanner(this._api) {
    _adapterSub = _api.adapterOn().listen(_onAdapterChanged);
    _resultsSub = _api.scanResults().listen(_observations.add);
  }

  final BlueZApi _api;
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();
  late final StreamSubscription<bool> _adapterSub;
  late final StreamSubscription<ScanObservation> _resultsSub;

  void _apply(ScannerEvent event) => _statuses.add(_machine.apply(event));

  Future<void> _onAdapterChanged(bool on) async {
    if (!on && _machine.status == ScannerStatus.scanning) {
      await _api.stopDiscovery();
      _apply(ScannerEvent.adapterOff);
    } else if (on && _machine.status == ScannerStatus.unavailable) {
      await _api.startDiscovery();
      _apply(ScannerEvent.adapterOn); // §5.4 auto-resume
    }
  }

  /// D-Bus policy denial maps here in the impl (NFR-6).
  void onPermissionRevoked() {
    if (_machine.status != ScannerStatus.unauthorized) {
      _apply(ScannerEvent.permissionRevoked);
    }
  }

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) async {
    if (_machine.status == ScannerStatus.scanning) return;
    await _api.startDiscovery();
    _apply(ScannerEvent.start);
  }

  @override
  Future<void> stop() async {
    if (_machine.status == ScannerStatus.idle) return; // idempotent
    await _api.stopDiscovery();
    _apply(ScannerEvent.stop);
  }
}
```

- [ ] **Step 4: Implement `lib/platform/bluez/bluez_api_impl.dart`**

```dart
import 'package:bluez/bluez.dart';

import '../../domain/types.dart';
import 'bluez_api.dart';

/// Real BlueZ D-Bus calls via package:bluez. Verify API names against
/// current package docs (context7 / pub.dev) at implementation time.
class BlueZApiImpl implements BlueZApi {
  BlueZApiImpl(this._client);

  final BlueZClient _client;

  BlueZAdapter get _adapter => _client.adapters.first;

  @override
  Stream<bool> adapterOn() => _adapter.propertiesChanged
      .where((props) => props.contains('Powered'))
      .map((_) => _adapter.powered);

  @override
  Stream<ScanObservation> scanResults() async* {
    await for (final device in _client.deviceAdded) {
      yield _toObservation(device);
    }
    // Note: also merge per-device RSSI propertiesChanged for already-known
    // devices — StreamGroup.merge from package:async:
    //   StreamGroup.merge([_client.deviceAdded.map(...), ...rssiStreams])
  }

  ScanObservation _toObservation(BlueZDevice d) => ScanObservation(
        deviceId: d.address,
        rssi: d.rssi.toDouble(),
        txPower: d.txPower == 0 ? null : d.txPower.toDouble(),
        timestamp: DateTime.now(),
        advertisedName: d.name.isEmpty ? null : d.name,
      );

  @override
  Future<void> startDiscovery() => _adapter.startDiscovery();

  @override
  Future<void> stopDiscovery() => _adapter.stopDiscovery();
}
```

- [ ] **Step 5: Run tests + commit**

Run: `flutter test test/platform/bluez_scanner_test.dart`
Expected: PASS (contract 5 + 1).

```bash
git add lib/platform/bluez test/platform/bluez_scanner_test.dart
git commit -m "feat: add BlueZ scanner adapter for Linux passing contract suite"
```

---

### Task 14: WebBluetoothScanner (Tier C)

**Files:**
- Create: `lib/platform/web/web_bluetooth_api.dart`
- Create: `lib/platform/web/web_bluetooth_scanner.dart`
- Create: `lib/platform/web/web_bluetooth_api_impl.dart`
- Test: `test/platform/web_bluetooth_scanner_test.dart`

**Interfaces:**
- Consumes: `BleScanner`, `ScannerStateMachine`, contract suite, ticker pattern from Task 8
- Produces: `WebBluetoothScanner({required WebBluetoothApi api, required Stream<DateTime> pollTicks}) implements BleScanner` plus `Future<void> pairNewDevice()` (invokes the browser chooser — the Tier C manual-discovery entry point, FR-3); `abstract interface class WebBluetoothApi { bool get isSupported; Future<String> requestDevice(); Future<double?> readRssi(String deviceId); Future<String?> deviceName(String deviceId); List<String> get pairedDeviceIds; }`

- [ ] **Step 1: Write the failing test**

`test/platform/web_bluetooth_scanner_test.dart`:

```dart
import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/web/web_bluetooth_api.dart';
import 'package:ble_tracker/platform/web/web_bluetooth_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

class FakeWebApi implements WebBluetoothApi {
  final Map<String, double?> rssiById = {};
  final Map<String, String?> nameById = {};
  bool supported = true;
  String? nextRequestedDevice;

  @override
  bool get isSupported => supported;

  @override
  List<String> get pairedDeviceIds => rssiById.keys.toList();

  @override
  Future<String> requestDevice() async {
    final id = nextRequestedDevice!;
    rssiById[id] = -60;
    return id;
  }

  @override
  Future<double?> readRssi(String deviceId) async => rssiById[deviceId];

  @override
  Future<String?> deviceName(String deviceId) async => nameById[deviceId];
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  runBleScannerContract('WebBluetoothScanner', () async {
    final api = FakeWebApi();
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    var tickCount = 0;
    return ScannerHarness(
      scanner: scanner,
      // Web has no advertisement push; emulate by setting RSSI and ticking.
      emitObservation: (obs) {
        api.rssiById[obs.deviceId] = obs.rssi;
        api.nameById[obs.deviceId] = obs.advertisedName;
        scanner.overrideNextTimestamp(obs.timestamp);
        // txPower is never present on Web (no advertisement access):
        // the contract's field-mapping test tolerates null txPower via
        // the harness capability flag below.
        ticks.add(obs.timestamp.add(Duration(seconds: ++tickCount)));
      },
      adapterOff: () => scanner.onAdapterChanged(false),
      adapterOn: () => scanner.onAdapterChanged(true),
      revokePermission: scanner.onPermissionRevoked,
    );
  });

  test('polls RSSI of paired devices on each tick while scanning', () async {
    final api = FakeWebApi();
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    api.rssiById['a'] = -55;
    final observations = <ScanObservation>[];
    scanner.observe().listen(observations.add);

    await scanner.start(ScanProfile.balanced);
    ticks.add(t0);
    await pumpEventQueue();
    expect(observations.single.deviceId, 'a');
    expect(observations.single.rssi, -55);

    await scanner.stop();
    ticks.add(t0.add(const Duration(seconds: 1)));
    await pumpEventQueue();
    expect(observations, hasLength(1)); // no polling when idle
  });

  test('pairNewDevice adds device via chooser and it gets polled', () async {
    final api = FakeWebApi()..nextRequestedDevice = 'new-dev';
    final ticks = StreamController<DateTime>.broadcast();
    final scanner = WebBluetoothScanner(api: api, pollTicks: ticks.stream);
    final observations = <ScanObservation>[];
    scanner.observe().listen(observations.add);
    await scanner.start(ScanProfile.balanced);
    await scanner.pairNewDevice();
    ticks.add(t0);
    await pumpEventQueue();
    expect(observations.single.deviceId, 'new-dev');
  });
}
```

The contract's field-mapping test asserts `txPower: -59` round-trips; Web can never supply txPower. Amend the contract suite (Task 11) with an optional capability flag:

```dart
void runBleScannerContract(
  String name,
  Future<ScannerHarness> Function() createHarness, {
  bool supportsTxPower = true,
  bool supportsAdvertisedName = true,
}) {
  // in the mapping test:
  //   expect(o.txPower, supportsTxPower ? -59 : isNull);
  //   expect(o.advertisedName, supportsAdvertisedName ? 'Buds' : anything);
}
```

Call it with `supportsTxPower: false` for the Web scanner. Also add `void overrideNextTimestamp(DateTime t)` to `WebBluetoothScanner` (test-only injection so polled observations carry deterministic timestamps; production passes tick time).

- [ ] **Step 2: Run to verify failure, then implement `lib/platform/web/web_bluetooth_scanner.dart`**

```dart
import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/scanner_state_machine.dart';
import '../../domain/types.dart';
import 'web_bluetooth_api.dart';

/// Tier C: no advertisement scanning. Polls RSSI of manually-paired devices
/// on each injected tick (≥ 1 Hz in production wiring, FR-18).
class WebBluetoothScanner implements BleScanner {
  WebBluetoothScanner({
    required WebBluetoothApi api,
    required Stream<DateTime> pollTicks,
  }) : _api = api {
    _tickSub = pollTicks.listen(_onTick);
  }

  final WebBluetoothApi _api;
  final _machine = ScannerStateMachine();
  final _observations = StreamController<ScanObservation>.broadcast();
  final _statuses = StreamController<ScannerStatus>.broadcast();
  late final StreamSubscription<DateTime> _tickSub;
  DateTime? _timestampOverride;

  void _apply(ScannerEvent event) => _statuses.add(_machine.apply(event));

  void overrideNextTimestamp(DateTime t) => _timestampOverride = t;

  void onAdapterChanged(bool on) {
    if (!on && _machine.status == ScannerStatus.scanning) {
      _apply(ScannerEvent.adapterOff);
    } else if (on && _machine.status == ScannerStatus.unavailable) {
      _apply(ScannerEvent.adapterOn);
    }
  }

  void onPermissionRevoked() {
    if (_machine.status != ScannerStatus.unauthorized) {
      _apply(ScannerEvent.permissionRevoked);
    }
  }

  Future<void> pairNewDevice() async {
    await _api.requestDevice();
  }

  Future<void> _onTick(DateTime now) async {
    if (_machine.status != ScannerStatus.scanning) return;
    for (final id in _api.pairedDeviceIds) {
      final rssi = await _api.readRssi(id);
      if (rssi == null) continue;
      _observations.add(ScanObservation(
        deviceId: id,
        rssi: rssi,
        timestamp: _timestampOverride ?? now,
        advertisedName: await _api.deviceName(id),
      ));
    }
    _timestampOverride = null;
  }

  @override
  Stream<ScanObservation> observe() => _observations.stream;

  @override
  Stream<ScannerStatus> status() async* {
    yield _machine.status;
    yield* _statuses.stream;
  }

  @override
  Future<void> start(ScanProfile profile) async {
    if (_machine.status == ScannerStatus.scanning) return;
    if (!_api.isSupported) {
      _apply(ScannerEvent.permissionRevoked); // surfaces unauthorized on Safari
      return;
    }
    _apply(ScannerEvent.start);
  }

  @override
  Future<void> stop() async {
    if (_machine.status == ScannerStatus.idle) return;
    _apply(ScannerEvent.stop);
  }
}
```

Note: unsupported-browser (Safari) UX is handled in the UI via `PlatformCapabilities` + a dedicated message (Task 17); mapping unsupported → `unauthorized` here is a belt-and-braces fallback.

- [ ] **Step 3: Implement `lib/platform/web/web_bluetooth_api_impl.dart`**

Real implementation over `package:flutter_web_bluetooth` (guarded so it only compiles on web via conditional import `if (dart.library.js_interop)`). Web Bluetooth exposes RSSI via `watchAdvertisements()` events, not a direct read — implement `readRssi` as "latest advertisement RSSI seen for this device", cached from the advertisement event stream:

```dart
import 'dart:async';

import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';

import 'web_bluetooth_api.dart';

/// Verify exact flutter_web_bluetooth API names against current docs
/// (context7 / pub.dev) at implementation time; advertisement watching
/// requires Chromium ≥ 111 with no flag.
class WebBluetoothApiImpl implements WebBluetoothApi {
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, double> _latestRssi = {};

  @override
  bool get isSupported => FlutterWebBluetooth.instance.isBluetoothApiSupported;

  @override
  List<String> get pairedDeviceIds => _devices.keys.toList();

  @override
  Future<String> requestDevice() async {
    final device = await FlutterWebBluetooth.instance.requestDevice(
      RequestOptionsBuilder.acceptAllDevices(),
    );
    _devices[device.id] = device;
    device.advertisements.listen((event) {
      final rssi = event.rssi;
      if (rssi != null) _latestRssi[device.id] = rssi.toDouble();
    });
    await device.watchAdvertisements();
    return device.id;
  }

  @override
  Future<double?> readRssi(String deviceId) async => _latestRssi[deviceId];

  @override
  Future<String?> deviceName(String deviceId) async =>
      _devices[deviceId]?.name;
}
```

- [ ] **Step 4: Run tests + commit**

Run: `flutter test test/platform/web_bluetooth_scanner_test.dart test/contract`
Expected: PASS (contract with `supportsTxPower: false` + 2 extra; smoke contract still green after the flag refactor).

```bash
git add lib/platform/web test/platform/web_bluetooth_scanner_test.dart test/contract/ble_scanner_contract.dart
git commit -m "feat: add Web Bluetooth polling scanner for Tier C"
```

---

### Task 15: WearScanner (Wear OS lifecycle wrapper)

**Files:**
- Create: `lib/platform/wear/wear_scanner.dart`
- Test: `test/platform/wear_scanner_test.dart`

**Interfaces:**
- Consumes: `BleScanner` (delegate), contract suite
- Produces: `WearScanner({required BleScanner inner, required Stream<bool> isAmbient}) implements BleScanner` — delegates everything to `inner` (the Android `FlutterBluePlusScanner`), but forces `ScanProfile.balanced` while ambient and pauses/resumes scanning across ambient transitions (Tier B: accepts OS throttling, §FR-19).

- [ ] **Step 1: Write the failing test**

`test/platform/wear_scanner_test.dart`:

```dart
import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/platform/wear/wear_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contract/ble_scanner_contract.dart';

void main() {
  runBleScannerContract('WearScanner', () async {
    final inner = FakeBleScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);
    return ScannerHarness(
      scanner: scanner,
      emitObservation: inner.emit,
      adapterOff: inner.setAdapterOff,
      adapterOn: inner.setAdapterOn,
      revokePermission: inner.revokePermission,
    );
  });

  test('ambient mode restarts inner scan with balanced profile', () async {
    final inner = _ProfileRecordingScanner();
    final ambient = StreamController<bool>.broadcast();
    final scanner = WearScanner(inner: inner, isAmbient: ambient.stream);

    await scanner.start(ScanProfile.lowLatency);
    expect(inner.profiles, [ScanProfile.lowLatency]);

    ambient.add(true);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.balanced);

    ambient.add(false);
    await pumpEventQueue();
    expect(inner.profiles.last, ScanProfile.lowLatency); // restore requested
  });
}

class _ProfileRecordingScanner implements BleScanner {
  final profiles = <ScanProfile>[];
  @override
  Stream<ScanObservation> observe() => const Stream.empty();
  @override
  Stream<ScannerStatus> status() => const Stream.empty();
  @override
  Future<void> start(ScanProfile profile) async => profiles.add(profile);
  @override
  Future<void> stop() async {}
}
```

- [ ] **Step 2: Run to verify failure, then implement `lib/platform/wear/wear_scanner.dart`**

```dart
import 'dart:async';

import '../../domain/interfaces.dart';
import '../../domain/types.dart';

/// Tier B wrapper: full delegate, but ambient (watch-face-visible) mode
/// downgrades to balanced scanning; leaving ambient restores the
/// requested profile (FR-19 / NFR-4).
class WearScanner implements BleScanner {
  WearScanner({required BleScanner inner, required Stream<bool> isAmbient})
      : _inner = inner {
    _ambientSub = isAmbient.listen(_onAmbient);
  }

  final BleScanner _inner;
  late final StreamSubscription<bool> _ambientSub;
  ScanProfile _requestedProfile = ScanProfile.balanced;
  bool _started = false;

  Future<void> _onAmbient(bool ambient) async {
    if (!_started) return;
    await _inner.start(
        ambient ? ScanProfile.balanced : _requestedProfile);
  }

  @override
  Stream<ScanObservation> observe() => _inner.observe();

  @override
  Stream<ScannerStatus> status() => _inner.status();

  @override
  Future<void> start(ScanProfile profile) async {
    _requestedProfile = profile;
    _started = true;
    await _inner.start(profile);
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _inner.stop();
  }
}
```

Note the contract test drives `inner` (a `FakeBleScanner`) whose `start` when already scanning throws `IllegalTransitionError` — but `FakeBleScanner.start` applies the event blindly. Guard `FakeBleScanner.start`/`stop` with the same idempotence used by real adapters (`if (currentStatus == ScannerStatus.scanning) return;` etc.) as part of this task, and re-run the Task 11 smoke test.

- [ ] **Step 3: Run tests + commit**

Run: `flutter test test/platform/wear_scanner_test.dart test/contract/contract_smoke_test.dart`
Expected: PASS.

```bash
git add lib/platform/wear test/platform/wear_scanner_test.dart lib/platform/fake_ble_scanner.dart
git commit -m "feat: add Wear OS scanner wrapper with ambient-mode throttling"
```

---

### Task 16: Platform capabilities detection

**Files:**
- Create: `lib/platform/default_platform_capabilities.dart`
- Test: `test/platform/platform_capabilities_test.dart`

**Interfaces:**
- Consumes: `PlatformCapabilities`, `CapabilityTier`
- Produces: `DefaultPlatformCapabilities({required TargetPlatform platform, required bool isWeb, bool isWatch = false}) implements PlatformCapabilities`

- [ ] **Step 1: Write the failing test**

`test/platform/platform_capabilities_test.dart`:

```dart
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/default_platform_capabilities.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DefaultPlatformCapabilities caps(TargetPlatform p,
          {bool web = false, bool watch = false}) =>
      DefaultPlatformCapabilities(platform: p, isWeb: web, isWatch: watch);

  test('Tier A: Android, Windows, macOS, Linux', () {
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      final c = caps(p);
      expect(c.tier, CapabilityTier.tierA, reason: '$p');
      expect(c.supportsAutoDiscovery, isTrue);
      expect(c.supportsBackgroundScan, isTrue);
    }
  });

  test('Tier B: iOS and Wear OS', () {
    final ios = caps(TargetPlatform.iOS);
    expect(ios.tier, CapabilityTier.tierB);
    expect(ios.supportsAutoDiscovery, isTrue);
    expect(ios.supportsBackgroundScan, isFalse);

    final wear = caps(TargetPlatform.android, watch: true);
    expect(wear.tier, CapabilityTier.tierB);
  });

  test('Tier C: web regardless of reported platform', () {
    final c = caps(TargetPlatform.android, web: true);
    expect(c.tier, CapabilityTier.tierC);
    expect(c.supportsAutoDiscovery, isFalse);
    expect(c.supportsBackgroundScan, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure, then implement `lib/platform/default_platform_capabilities.dart`**

```dart
import 'package:flutter/foundation.dart';

import '../domain/interfaces.dart';
import '../domain/types.dart';

class DefaultPlatformCapabilities implements PlatformCapabilities {
  DefaultPlatformCapabilities({
    required TargetPlatform platform,
    required bool isWeb,
    bool isWatch = false,
  }) : tier = isWeb
            ? CapabilityTier.tierC
            : (platform == TargetPlatform.iOS || isWatch)
                ? CapabilityTier.tierB
                : CapabilityTier.tierA;

  @override
  final CapabilityTier tier;

  @override
  bool get supportsAutoDiscovery => tier != CapabilityTier.tierC;

  @override
  bool get supportsBackgroundScan => tier == CapabilityTier.tierA;
}
```

- [ ] **Step 3: Run tests + commit**

Run: `flutter test test/platform/platform_capabilities_test.dart`
Expected: PASS (3 tests).

```bash
git add lib/platform/default_platform_capabilities.dart test/platform/platform_capabilities_test.dart
git commit -m "feat: add tier detection via platform capabilities"
```

---

### Task 17: Device list screen (tier-adaptive)

**Files:**
- Create: `lib/ui/device_list_screen.dart`
- Create: `lib/ui/scanner_status_banner.dart`
- Test: `test/ui/device_list_screen_test.dart`

**Interfaces:**
- Consumes: `deviceStatesProvider`, `deviceRegistryProvider`, `platformCapabilitiesProvider`, `bleScannerProvider`, `ScannerStatus`
- Produces: `DeviceListScreen extends ConsumerWidget` (route `/`); `ScannerStatusBanner extends ConsumerWidget` (reused by radar screen). Keys used by tests and later tasks: `Key('tracking-toggle-<deviceId>')`, `Key('auto-discover-note')`, `Key('manual-pair-button')`, `Key('unsupported-browser-message')`, `Key('status-banner')`.

- [ ] **Step 1: Write the failing widget test**

`test/ui/device_list_screen_test.dart`:

```dart
import 'dart:async';

import 'package:ble_tracker/domain/interfaces.dart';
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/default_platform_capabilities.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/device_list_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingRegistry implements DeviceRegistry {
  RecordingRegistry(this.devices);
  final List<RegisteredDevice> devices;
  final calls = <(String, Object?)>[];
  final _controller = StreamController<List<RegisteredDevice>>.broadcast();

  @override
  Stream<List<RegisteredDevice>> watchAll() async* {
    yield devices;
    yield* _controller.stream;
  }

  @override
  Future<void> register(RegisteredDevice device) async =>
      calls.add(('register', device));
  @override
  Future<void> setTracking(String deviceId, bool enabled) async =>
      calls.add(('setTracking', (deviceId, enabled)));
  @override
  Future<void> rename(String deviceId, String name) async =>
      calls.add(('rename', (deviceId, name)));
  @override
  Future<void> remove(String deviceId) async => calls.add(('remove', deviceId));
}

Widget app(List<Override> overrides) => ProviderScope(
    overrides: overrides, child: const MaterialApp(home: DeviceListScreen()));

List<Override> overridesWith({
  required RecordingRegistry registry,
  required FakeBleScanner scanner,
  CapabilityTier tier = CapabilityTier.tierA,
}) {
  final ticks = StreamController<DateTime>.broadcast();
  return [
    deviceRegistryProvider.overrideWithValue(registry),
    bleScannerProvider.overrideWithValue(scanner),
    tickerProvider.overrideWithValue(ticks.stream),
    platformCapabilitiesProvider.overrideWithValue(
      DefaultPlatformCapabilities(
        platform: TargetPlatform.android,
        isWeb: tier == CapabilityTier.tierC,
      ),
    ),
  ];
}

RegisteredDevice dev(String id, {bool tracking = true}) => RegisteredDevice(
    id: id, name: 'Device $id', type: DeviceType.tag,
    trackingEnabled: tracking);

void main() {
  testWidgets('renders all three visibility states', (tester) async {
    final registry = RecordingRegistry([dev('a'), dev('b'), dev('c', tracking: false)]);
    final scanner = FakeBleScanner();
    await tester.pumpWidget(app(overridesWith(registry: registry, scanner: scanner)));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    scanner.emit(ScanObservation(
        deviceId: 'a', rssi: -59, txPower: -59, timestamp: DateTime.utc(2026)));
    await tester.pump();

    expect(find.textContaining('1.0 m'), findsOneWidget); // a: visible + distance
    expect(find.textContaining('near'), findsOneWidget); // FR-11 band shown
    expect(find.text('Not visible'), findsOneWidget); // b
    expect(find.text('Tracking off'), findsOneWidget); // c
  });

  testWidgets('toggle dispatches setTracking', (tester) async {
    final registry = RecordingRegistry([dev('a')]);
    await tester.pumpWidget(app(
        overridesWith(registry: registry, scanner: FakeBleScanner())));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tracking-toggle-a')));
    await tester.pump();
    expect(registry.calls, contains(('setTracking', ('a', false))));
  });

  testWidgets('Tier A shows auto-discovery note, no manual pair button',
      (tester) async {
    await tester.pumpWidget(app(overridesWith(
        registry: RecordingRegistry([]), scanner: FakeBleScanner())));
    await tester.pump();
    expect(find.byKey(const Key('auto-discover-note')), findsOneWidget);
    expect(find.byKey(const Key('manual-pair-button')), findsNothing);
  });

  testWidgets('Tier C hides auto-discovery, shows manual pair', (tester) async {
    await tester.pumpWidget(app(overridesWith(
        registry: RecordingRegistry([]),
        scanner: FakeBleScanner(),
        tier: CapabilityTier.tierC)));
    await tester.pump();
    expect(find.byKey(const Key('auto-discover-note')), findsNothing);
    expect(find.byKey(const Key('manual-pair-button')), findsOneWidget);
  });

  testWidgets('status banner surfaces unavailable and unauthorized states',
      (tester) async {
    final scanner = FakeBleScanner();
    await tester.pumpWidget(app(
        overridesWith(registry: RecordingRegistry([]), scanner: scanner)));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    scanner.setAdapterOff();
    await tester.pump();
    expect(find.textContaining('Bluetooth is off'), findsOneWidget);
    scanner.setAdapterOn();
    await tester.pump();
    expect(find.textContaining('Bluetooth is off'), findsNothing);
    scanner.revokePermission();
    await tester.pump();
    expect(find.textContaining('permission'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure, then implement `lib/ui/scanner_status_banner.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';

/// NFR-6: adapter-off / permission-revoked surface as a recoverable banner.
class ScannerStatusBanner extends ConsumerWidget {
  const ScannerStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(scannerStatusProvider).valueOrNull;
    final (text, color) = switch (status) {
      ScannerStatus.unavailable => (
          'Bluetooth is off — turn it on to resume tracking.',
          Colors.orange
        ),
      ScannerStatus.unauthorized => (
          'Bluetooth permission needed — grant permission to scan.',
          Colors.red
        ),
      _ => (null, Colors.transparent),
    };
    if (text == null) return const SizedBox.shrink();
    return Material(
      key: const Key('status-banner'),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
```

Add to `lib/state/providers.dart` (and regenerate):

```dart
@Riverpod(keepAlive: true)
Stream<ScannerStatus> scannerStatus(Ref ref) =>
    ref.watch(bleScannerProvider).status();
```

- [ ] **Step 3: Implement `lib/ui/device_list_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';
import 'scanner_status_banner.dart';

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(deviceStatesProvider).valueOrNull ?? {};
    final caps = ref.watch(platformCapabilitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Column(
        children: [
          const ScannerStatusBanner(),
          if (caps.supportsAutoDiscovery)
            const ListTile(
              key: Key('auto-discover-note'),
              leading: Icon(Icons.radar),
              title: Text('Known devices are re-acquired automatically.'),
            )
          else
            ListTile(
              key: const Key('manual-pair-button'),
              leading: const Icon(Icons.add_link),
              title: const Text('Pair a device'),
              subtitle: const Text(
                  'This browser only supports manually paired devices.'),
              onTap: () {
                // Wired to WebBluetoothScanner.pairNewDevice in Task 19.
              },
            ),
          Expanded(
            child: ListView(
              children: [
                for (final s in states.values)
                  ListTile(
                    leading: Icon(_iconFor(s.device.type)),
                    title: Text(s.device.name),
                    subtitle: Text(_statusLine(s)),
                    trailing: Switch(
                      key: Key('tracking-toggle-${s.device.id}'),
                      value: s.device.trackingEnabled,
                      onChanged: (v) => ref
                          .read(deviceRegistryProvider)
                          .setTracking(s.device.id, v),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(DeviceType type) => switch (type) {
        DeviceType.headphones => Icons.headphones,
        DeviceType.phone => Icons.smartphone,
        DeviceType.tag => Icons.sell,
        DeviceType.watch => Icons.watch,
        DeviceType.other => Icons.bluetooth,
      };

  String _statusLine(TrackedDeviceState s) => switch (s.visibility) {
        DeviceVisibility.visible =>
          '${s.estimate!.meters.toStringAsFixed(1)} m · ${s.estimate!.band.name}',
        DeviceVisibility.notVisible => 'Not visible',
        DeviceVisibility.trackingOff => 'Tracking off',
      };
}
```

Note FR-11: distance shown with one decimal + band name together.

- [ ] **Step 4: Run tests, regenerate providers, iterate to green**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/ui/device_list_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui lib/state/providers.dart lib/state/providers.g.dart test/ui
git commit -m "feat: add tier-adaptive device list with status banner"
```

---

### Task 18: Radar screen, painter, goldens, device detail

**Files:**
- Create: `lib/ui/radar_screen.dart`
- Create: `lib/ui/radar_painter.dart`
- Create: `lib/ui/device_detail_sheet.dart`
- Test: `test/ui/radar_screen_test.dart`
- Test: `test/ui/radar_golden_test.dart` (+ goldens under `test/ui/goldens/`)

**Interfaces:**
- Consumes: `radarBlipsFrom`, `hitTestBlips`, `RadarBlip`, `deviceStatesProvider`, `radarLayoutProvider`, `proximityConfigProvider`, `ScannerStatusBanner`
- Produces: `RadarScreen extends ConsumerStatefulWidget`; `RadarPainter extends CustomPainter` with constructor `RadarPainter({required List<RadarBlip> blips, required double sweepAngle, required List<double> ringRadii})`; `DeviceDetailSheet extends ConsumerWidget` (constructor takes `String deviceId`) showing name, raw RSSI, smoothed distance, band, last-seen (FR-17). Raw RSSI reaches the sheet via a `latestRssiProvider` (map of deviceId → last raw RSSI, fed from `bleScannerProvider.observe()`).

- [ ] **Step 1: Write failing widget tests `test/ui/radar_screen_test.dart`**

```dart
import 'dart:async';

import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/state/providers.dart';
import 'package:ble_tracker/ui/device_detail_sheet.dart';
import 'package:ble_tracker/ui/radar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, overridesWith, dev;

void main() {
  testWidgets('blip renders for visible device and tap opens detail sheet',
      (tester) async {
    final scanner = FakeBleScanner();
    final registry = RecordingRegistry([dev('a')]);
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(registry: registry, scanner: scanner),
      child: const MaterialApp(home: RadarScreen()),
    ));
    await tester.pump();
    await scanner.start(ScanProfile.balanced);
    scanner.emit(ScanObservation(
        deviceId: 'a', rssi: -59, txPower: -59, timestamp: DateTime.utc(2026)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Tap at the blip's computed position.
    final radar = find.byKey(const Key('radar-canvas'));
    expect(radar, findsOneWidget);
    final state = tester.state<RadarScreenState>(find.byType(RadarScreen));
    final blip = state.currentBlips.single;
    final box = tester.renderObject<RenderBox>(radar);
    final center = box.size.center(Offset.zero);
    final canvasRadius = box.size.shortestSide / 2;
    final tapLocal = center +
        Offset.fromDirection(blip.angle, blip.radius * canvasRadius);
    await tester.tapAt(box.localToGlobal(tapLocal));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceDetailSheet), findsOneWidget);
    expect(find.textContaining('Device a'), findsWidgets); // name
    expect(find.textContaining('-59'), findsOneWidget); // raw RSSI
    expect(find.textContaining('1.0 m'), findsOneWidget); // smoothed distance
    expect(find.textContaining('near'), findsOneWidget); // band
  });

  testWidgets('sweep animation advances between frames', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: FakeBleScanner()),
      child: const MaterialApp(home: RadarScreen()),
    ));
    await tester.pump();
    final state = tester.state<RadarScreenState>(find.byType(RadarScreen));
    final a1 = state.sweepAngle;
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.sweepAngle, isNot(a1));
  });
}
```

- [ ] **Step 2: Write the golden test `test/ui/radar_golden_test.dart`**

```dart
import 'package:ble_tracker/state/radar_blips.dart';
import 'package:ble_tracker/ui/radar_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget paint(List<RadarBlip> blips) => RepaintBoundary(
        child: Container(
          color: const Color(0xFF0A1410),
          width: 400,
          height: 400,
          child: CustomPaint(
            painter: RadarPainter(
              blips: blips,
              sweepAngle: 1.0, // fixed for determinism
              ringRadii: const [0.25, 0.5, 0.75, 1.0],
            ),
          ),
        ),
      );

  testWidgets('golden: one blip per band ring', (tester) async {
    await tester.pumpWidget(paint(const [
      RadarBlip(deviceId: 'a', name: 'a', angle: 0.3, radius: 0.15, opacity: 1),
      RadarBlip(deviceId: 'b', name: 'b', angle: 1.8, radius: 0.4, opacity: 1),
      RadarBlip(deviceId: 'c', name: 'c', angle: 3.5, radius: 0.65, opacity: 1),
      RadarBlip(deviceId: 'd', name: 'd', angle: 5.2, radius: 0.9, opacity: 1),
    ]));
    await expectLater(find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/radar_four_bands.png'));
  });

  testWidgets('golden: fading blip at half opacity', (tester) async {
    await tester.pumpWidget(paint(const [
      RadarBlip(deviceId: 'a', name: 'a', angle: 0.3, radius: 0.5, opacity: 0.5),
    ]));
    await expectLater(find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/radar_fading_blip.png'));
  });

  testWidgets('golden: empty radar', (tester) async {
    await tester.pumpWidget(paint(const []));
    await expectLater(find.byType(RepaintBoundary),
        matchesGoldenFile('goldens/radar_empty.png'));
  });
}
```

- [ ] **Step 3: Implement `lib/ui/radar_painter.dart`**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/radar_blips.dart';

class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.blips,
    required this.sweepAngle,
    required this.ringRadii,
  });

  final List<RadarBlip> blips;
  final double sweepAngle;
  final List<double> ringRadii; // fractions of canvas radius, one per band

  static const _ringColor = Color(0xFF1E4D3A);
  static const _blipColor = Color(0xFF4ADE80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _ringColor;
    for (final r in ringRadii) {
      canvas.drawCircle(center, r * radius, ringPaint);
    }

    // Cosmetic sweep (FR-16): gradient wedge trailing the sweep angle.
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.8,
        endAngle: sweepAngle,
        colors: const [Color(0x004ADE80), Color(0x334ADE80)],
        transform: GradientRotation(sweepAngle - 0.8),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // Center dot = the user (FR-13).
    canvas.drawCircle(center, 5, Paint()..color = _blipColor);

    for (final blip in blips) {
      final pos = center +
          Offset.fromDirection(blip.angle, blip.radius * radius);
      final paint = Paint()
        ..color = _blipColor.withValues(alpha: blip.opacity);
      canvas.drawCircle(pos, 7, paint);
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _blipColor.withValues(alpha: blip.opacity * 0.4);
      canvas.drawCircle(pos, 11, halo);
    }
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.blips != blips ||
      old.sweepAngle != sweepAngle ||
      old.ringRadii != ringRadii;
}
```

- [ ] **Step 4: Implement `lib/ui/radar_screen.dart`**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';
import '../state/radar_blips.dart';
import 'device_detail_sheet.dart';
import 'radar_painter.dart';
import 'scanner_status_banner.dart';

class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  @override
  ConsumerState<RadarScreen> createState() => RadarScreenState();
}

class RadarScreenState extends ConsumerState<RadarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  Map<String, double> _lastKnownRadius = {};
  List<RadarBlip> currentBlips = [];

  double get sweepAngle => _sweep.value * 2 * math.pi;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat(); // FR-16; Flutter degrades frame rate gracefully under load
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final states = ref.watch(deviceStatesProvider).valueOrNull ?? {};
    final layout = ref.watch(radarLayoutProvider);
    final config = ref.watch(proximityConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Radar')),
      body: Column(
        children: [
          const ScannerStatusBanner(),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    currentBlips = radarBlipsFrom(
                      states,
                      DateTime.now(),
                      layout,
                      config,
                      lastKnownRadius: _lastKnownRadius,
                    );
                    _lastKnownRadius = {
                      for (final b in currentBlips) b.deviceId: b.radius,
                    };
                    return GestureDetector(
                      key: const Key('radar-canvas'),
                      onTapUp: (details) => _onTap(context, details),
                      child: CustomPaint(
                        painter: RadarPainter(
                          blips: currentBlips,
                          sweepAngle: sweepAngle,
                          ringRadii: const [0.25, 0.5, 0.75, 1.0],
                        ),
                        child: const SizedBox.expand(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context, TapUpDetails details) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    final center = box.size.center(Offset.zero);
    final canvasRadius = box.size.shortestSide / 2;
    final id = hitTestBlips(
      currentBlips,
      (dx: local.dx - center.dx, dy: local.dy - center.dy),
      canvasRadius,
    );
    if (id != null) {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => DeviceDetailSheet(deviceId: id),
      );
    }
  }
}
```

Note: `DateTime.now()` here is UI-frame-time for fade rendering only — all *logic* time stays injected; the widget test controls it indirectly via observation timestamps, and the fade math itself is already covered by pure tests (Task 9). Ring radii `[0.25, 0.5, 0.75, 1.0]` correspond to the four bands' outer edges under the log mapping — compute them from `layout.radiusFor` at the band boundary distances instead of hard-coding, e.g. in `build`:

```dart
final ringRadii = [
  layout.radiusFor(DistanceEstimate(meters: config.immediateMaxMeters, band: ProximityBand.immediate)),
  layout.radiusFor(DistanceEstimate(meters: config.nearMaxMeters, band: ProximityBand.near)),
  layout.radiusFor(DistanceEstimate(meters: config.midMaxMeters, band: ProximityBand.mid)),
  1.0,
];
```

(FR-13: rings map to bands — use this computed version, keep the golden test's fixed radii as painter-level inputs.)

- [ ] **Step 5: Implement `lib/ui/device_detail_sheet.dart`** and `latestRssiProvider`

Add to `lib/state/providers.dart`:

```dart
@Riverpod(keepAlive: true)
Stream<Map<String, double>> latestRssi(Ref ref) async* {
  final latest = <String, double>{};
  await for (final obs in ref.watch(bleScannerProvider).observe()) {
    latest[obs.deviceId] = obs.rssi;
    yield Map.of(latest);
  }
}
```

`lib/ui/device_detail_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';

/// FR-17: name, raw RSSI, smoothed distance, band, last-seen.
class DeviceDetailSheet extends ConsumerWidget {
  const DeviceDetailSheet({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(deviceStatesProvider).valueOrNull?[deviceId];
    final rssi = ref.watch(latestRssiProvider).valueOrNull?[deviceId];
    if (state == null) return const SizedBox.shrink();
    final e = state.estimate;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.device.name,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Raw RSSI: ${rssi?.toStringAsFixed(0) ?? '—'} dBm'),
          Text(e == null
              ? 'Distance: —'
              : 'Distance: ${e.meters.toStringAsFixed(1)} m (${e.band.name})'),
          Text('Last seen: ${state.lastSeen?.toLocal() ?? 'never'}'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Generate goldens, run all UI tests**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test --update-goldens test/ui/radar_golden_test.dart && flutter test test/ui`
Expected: goldens created under `test/ui/goldens/`; all UI tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ui lib/state test/ui
git commit -m "feat: add radar screen with painter, goldens, and device detail"
```

---

### Task 19: App shell, wiring, discovery flow, coverage gate, manual checklist

**Files:**
- Create: `lib/ui/app.dart`
- Modify: `lib/main.dart` (replace scaffold counter app)
- Create: `lib/ui/discovery_screen.dart`
- Create: `tool/coverage_gate.dart`
- Create: `docs/manual-test-checklist.md`
- Modify: `.github/workflows/ci.yml` (add coverage gate step)
- Test: `test/ui/app_shell_test.dart`
- Delete: `test/widget_test.dart` (scaffold counter test)

**Interfaces:**
- Consumes: everything prior
- Produces: `BleTrackerApp` (tabbed shell: Radar / Devices / Discover), `main()` wiring real adapters per platform, CI gate enforcing 100% on `domain/` + `state/`.

- [ ] **Step 1: Write the failing shell test `test/ui/app_shell_test.dart`**

```dart
import 'package:ble_tracker/domain/types.dart';
import 'package:ble_tracker/platform/fake_ble_scanner.dart';
import 'package:ble_tracker/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_list_screen_test.dart' show RecordingRegistry, overridesWith;

void main() {
  testWidgets(
      'NFR-4: radar tab starts lowLatency scan, devices tab switches to balanced',
      (tester) async {
    final scanner = _ProfileSpy();
    await tester.pumpWidget(ProviderScope(
      overrides: overridesWith(
          registry: RecordingRegistry([]), scanner: scanner.fake),
      child: const BleTrackerApp(),
    ));
    await tester.pumpAndSettle();

    expect(scanner.profiles.last, ScanProfile.lowLatency); // radar is home tab

    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(scanner.profiles.last, ScanProfile.balanced);
  });
}

class _ProfileSpy {
  final fake = FakeBleScanner();
  List<ScanProfile> get profiles => fake.startedProfiles;
}
```

Add `final startedProfiles = <ScanProfile>[];` to `FakeBleScanner.start` (record then apply) as part of this task.

- [ ] **Step 2: Implement `lib/ui/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';
import 'device_list_screen.dart';
import 'discovery_screen.dart';
import 'radar_screen.dart';

class BleTrackerApp extends ConsumerStatefulWidget {
  const BleTrackerApp({super.key});

  @override
  ConsumerState<BleTrackerApp> createState() => _BleTrackerAppState();
}

class _BleTrackerAppState extends ConsumerState<BleTrackerApp> {
  int _tab = 0;

  static const _profiles = [
    ScanProfile.lowLatency, // radar (NFR-4)
    ScanProfile.balanced, // device list
    ScanProfile.balanced, // discovery
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleScannerProvider).start(_profiles[_tab]);
    });
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    final scanner = ref.read(bleScannerProvider);
    scanner.stop().then((_) => scanner.start(_profiles[i]));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Tracker',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: const [RadarScreen(), DeviceListScreen(), DiscoveryScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
            NavigationDestination(
                icon: Icon(Icons.devices), label: 'Devices'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Discover'),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement `lib/ui/discovery_screen.dart`** (FR-1 manual discovery)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';

/// FR-1: scan results the user can register. Observations from devices not
/// yet in the registry are listed here with a Track button.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final Map<String, ScanObservation> _seen = {};

  @override
  Widget build(BuildContext context) {
    ref.listen(discoveryObservationsProvider, (_, next) {
      next.whenData((obs) => setState(() => _seen[obs.deviceId] = obs));
    });
    final registered =
        ref.watch(deviceStatesProvider).valueOrNull?.keys.toSet() ?? {};
    final unregistered =
        _seen.values.where((o) => !registered.contains(o.deviceId)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: ListView(
        children: [
          for (final o in unregistered)
            ListTile(
              leading: const Icon(Icons.bluetooth_searching),
              title: Text(o.advertisedName ?? o.deviceId),
              subtitle: Text('${o.rssi.toStringAsFixed(0)} dBm'),
              trailing: FilledButton(
                child: const Text('Track'),
                onPressed: () => ref.read(deviceRegistryProvider).register(
                      RegisteredDevice(
                        id: o.deviceId,
                        name: o.advertisedName ?? o.deviceId,
                        type: DeviceType.other,
                      ),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
```

Add to providers (+ regen): `@Riverpod(keepAlive: true) Stream<ScanObservation> discoveryObservations(Ref ref) => ref.watch(bleScannerProvider).observe();`

- [ ] **Step 4: Implement `lib/main.dart`** (real wiring; excluded from coverage gate)

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/interfaces.dart';
import 'platform/default_platform_capabilities.dart';
import 'platform/fbp/fbp_api_impl.dart';
import 'platform/fbp/flutter_blue_plus_scanner.dart';
import 'platform/shared_prefs_store.dart';
import 'domain/persistent_device_registry.dart';
import 'state/providers.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final caps = DefaultPlatformCapabilities(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
  );
  final BleScanner scanner = _scannerFor(caps);
  runApp(ProviderScope(
    overrides: [
      bleScannerProvider.overrideWithValue(scanner),
      deviceRegistryProvider
          .overrideWithValue(PersistentDeviceRegistry(SharedPrefsStore())),
      platformCapabilitiesProvider.overrideWithValue(caps),
      tickerProvider.overrideWithValue(
        Stream<DateTime>.periodic(
            const Duration(seconds: 1), (_) => DateTime.now()),
      ),
    ],
    child: const BleTrackerApp(),
  ));
}

BleScanner _scannerFor(PlatformCapabilities caps) {
  // Web and Linux wiring use conditional imports so dart:js_interop /
  // D-Bus code never reaches other platforms:
  //   - lib/platform/scanner_factory_io.dart  (fbp / bluez / wear)
  //   - lib/platform/scanner_factory_web.dart (WebBluetoothScanner)
  // imported via:  import 'platform/scanner_factory_io.dart'
  //     if (dart.library.js_interop) 'platform/scanner_factory_web.dart';
  // For this step, wire the flutter_blue_plus path and add the factory
  // split as the follow-up commit in this task:
  return FlutterBluePlusScanner(FbpApiImpl());
}
```

Then add the two factory files exactly as the comment describes (each exporting `BleScanner createScanner(PlatformCapabilities caps, Stream<DateTime> ticks)`; the io one returns `BlueZScanner(BlueZApiImpl(...))` on Linux, `FlutterBluePlusScanner(FbpApiImpl())` elsewhere; the web one returns `WebBluetoothScanner(...)`), and replace `_scannerFor` with the conditional import. Wear detection: Wear OS apps are built from a dedicated flavor — pass `isWatch: const bool.fromEnvironment('WEAR_OS')` into capabilities and wrap the scanner in `WearScanner` when set (ambient stream from the `flutter_wear_os_connectivity`-style plugin is deferred to manual wiring; a `const Stream<bool>.empty()` placeholder is functionally correct — no ambient events means no throttling).

- [ ] **Step 5: Implement `tool/coverage_gate.dart`**

```dart
import 'dart:io';

/// §7.6: fail below 100% line coverage on lib/domain/ and lib/state/.
void main() {
  final lcov = File('coverage/lcov.info').readAsLinesSync();
  String? currentFile;
  var relevant = false;
  var found = 0;
  var hit = 0;
  final misses = <String>[];

  for (final line in lcov) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      relevant = currentFile.contains('lib/domain/') ||
          currentFile.contains('lib/state/');
    } else if (relevant && line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      found++;
      if (int.parse(parts[1]) > 0) {
        hit++;
      } else {
        misses.add('$currentFile:${parts[0]}');
      }
    }
  }

  if (found == 0) {
    stderr.writeln('coverage_gate: no domain/state lines found in lcov.info');
    exit(1);
  }
  if (hit < found) {
    stderr.writeln('coverage_gate: ${found - hit} uncovered lines:');
    misses.forEach(stderr.writeln);
    exit(1);
  }
  stdout.writeln('coverage_gate: 100% ($hit/$found lines) on domain/ + state/');
}
```

Exclusion note: `providers.g.dart` is generated code inside `lib/state/` — add `// coverage:ignore-file` handling if the gate trips on it (extend the gate to skip files whose source contains `coverage:ignore-file`, or simpler: skip `*.g.dart` in the gate — do that in the SF: check: `!currentFile.endsWith('.g.dart')`).

- [ ] **Step 6: Add gate to CI**

Append to `.github/workflows/ci.yml` steps:

```yaml
      - run: dart run tool/coverage_gate.dart
```

- [ ] **Step 7: Write `docs/manual-test-checklist.md`** (§7.5 verbatim, as a per-release checklist)

```markdown
# Manual Test Checklist (per release)

Executed manually per release — replaces integration tests (§7.1).

- [ ] 1. Android + iOS: register headphones, verify band transitions walking away/toward.
- [ ] 2. Adapter off/on mid-session on each mobile platform → recoverable UI.
- [ ] 3. Permission revoke mid-session (Android) → unauthorized state, re-grant recovers.
- [ ] 4. Web (Chrome): manual pair, RSSI polling updates radar; Safari shows unsupported message.
- [ ] 5. Wear OS: foreground tracking of one device; background resume shows paused-state notice.
- [ ] 6. 20+ simultaneous devices on Android: radar remains ≥ 30 fps (visual check + DevTools).

Release: ____________  Tester: ____________  Date: ____________
```

- [ ] **Step 8: Delete scaffold test, run everything**

```bash
rm test/widget_test.dart
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
dart run tool/coverage_gate.dart
```

Expected: analyze clean; all tests pass; gate reports 100%. Any uncovered domain/state lines listed by the gate get tests added now (this is the enforcement moment for the §7.1 coverage target).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add app shell, platform wiring, coverage gate, manual checklist"
```

---

## Requirement → Task traceability

| Requirement | Task(s) |
|---|---|
| FR-1 manual discovery | 19 (DiscoveryScreen) |
| FR-2 auto re-acquisition | 8 (composer matches observations to registry automatically) |
| FR-3 Tier C fallback messaging | 14, 17 |
| FR-4 not-visible handling | 8 |
| FR-5 persistent registry | 7 |
| FR-6 no cap | 7 (1000-device test) |
| FR-7 tracking toggle excludes processing | 8, 17 |
| FR-8 live status per device | 8, 17 |
| FR-9 path loss model + TxPower fallback | 4 |
| FR-10 injected Kalman | 3 |
| FR-11 numeric + band display | 4, 17, 18 |
| FR-12 staleness + fade | 8, 9, 18 |
| FR-13 band rings | 18 |
| FR-14 log-scaled blips | 5, 18 |
| FR-15 deterministic pseudo-angles | 5 |
| FR-16 sweep animation | 18 |
| FR-17 blip tap → detail | 9, 18 |
| FR-18 continuous foreground scan / 1 Hz Tier C | 12–14, 19 |
| FR-19 per-tier background behavior | 15, 16 (Tier A background service deferred to manual wiring; surface documented) |
| NFR-1 precision framing | 4, 17 (band always shown with numeric) |
| NFR-2/3 latency | architecture (stream-direct path); manual checklist |
| NFR-4 scan profiles per screen | 12, 15, 19 |
| NFR-5 render performance | manual checklist item 6 |
| NFR-6 recoverable states | 6, 11–15, 17 (banner) |
| §5.4 state machine | 6, 11 |
| §7.3 contract suites | 11–15 |
| §7.6 CI + coverage gate + pinned goldens | 1, 19 |
| OQ-1 (shared_preferences) | 7 |
| OQ-2 (bluez package, not FFI) | 13 |
| OQ-3 (global n, v1) | 2 (config; per-device deferred per spec) |

Known deliberate v1 gaps (spec-sanctioned): Android foreground service for background scanning and Wear ambient-stream plugin wiring are platform-glue tasks verified via the manual checklist, not unit tests; Tier B "updates paused" resume notice is covered by the status banner pattern and manual checklist item 5. FR-9's "user-tunable in settings" clause is also descoped from v1: ProximityConfig is injected and ready to be driven by user input, but no settings UI exists yet — follow-up. FR-19's Tier C "stops when tab hidden" behavior has no page-visibility handling yet either — WebBluetoothScanner keeps polling on a hidden tab today — follow-up.
