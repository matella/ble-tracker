# BLE Proximity Tracker — Specification v1.0

**Status:** Draft
**Stack:** Flutter (Dart)
**Methodology:** Spec-Driven Development — interfaces spec'd first, implementations via TDD, full unit test coverage.

---

## 1. Overview

A multi-platform application that tracks the proximity of Bluetooth (BLE) devices — headphones, smartphones, tags, etc. — and displays them on a live "radar" UI. Distance is estimated from signal strength (RSSI), smoothed via filtering, and rendered in real time.

### 1.1 Goals (v1)

- Live proximity tracking of any number of BLE devices simultaneously.
- Radar-style visualization with distance rings.
- Manual and (where platform-supported) automatic device discovery.
- Device list with per-device tracking toggle (filter).
- Best achievable distance precision from RSSI; UWB is a future enhancement (see §9).

### 1.2 Non-Goals (v1)

- No out-of-range alerts / notifications.
- No location history or last-seen persistence — live state only.
- No cloud sync or multi-user features.
- No true directional bearing (requires UWB; radar angles are stable pseudo-angles).

---

## 2. Platform & Compatibility Matrix

All platforms are v1 targets. Minimum OS versions are set "fairly new" to maximize API availability.

| Capability | Android | iOS | Wear OS | Windows | macOS | Linux | Web |
|---|---|---|---|---|---|---|---|
| Min version | 12 (API 31) | 16 | Wear OS 4 | 10 21H2+ | 13 | BlueZ 5.60+ | Chromium-based only |
| Foreground continuous scan | ✅ | ✅ | ✅ (limited) | ✅ | ✅ | ✅ | ⚠️ paired devices only |
| Background scan | ✅ (foreground service) | ⚠️ throttled | ⚠️ heavily limited | ✅ | ✅ | ✅ | ❌ |
| Auto-discovery (advertisement scan) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ manual pair per device |
| RSSI access | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (connected devices) |
| Runtime permissions | BLUETOOTH_SCAN, BLUETOOTH_CONNECT | NSBluetoothAlwaysUsageDescription | as Android | none | Bluetooth privacy prompt | none | user gesture + chooser prompt |

**Capability tiers** (referenced throughout this spec):

- **Tier A (full):** Android, Windows, macOS, Linux — continuous scan + auto-discovery + background.
- **Tier B (reduced background):** iOS, Wear OS — full foreground capability; background scanning throttled by OS. UX must not promise real-time updates while backgrounded.
- **Tier C (manual-only):** Web — no advertisement scanning. Devices must be manually paired via the browser chooser; RSSI polled per connected device. No Safari support (Web Bluetooth unavailable); app must detect and show an unsupported-browser message.

The UI must adapt to the running tier (e.g., hide "auto-discover" on Web) — tier detection is part of the platform abstraction layer (§5.2).

---

## 3. Functional Specification

### 3.1 Device Discovery

**FR-1** — The app SHALL support **manual discovery**: user initiates a scan, results are listed, user selects devices to track.

**FR-2** — The app SHALL support **automatic discovery** on Tier A/B platforms: known previously-tracked devices detected in advertisement scans are re-acquired without user action.

**FR-3** — On platforms where automatic discovery is unavailable (Tier C), the app SHALL fall back to manual-only and communicate this in the UI.

**FR-4** — The app SHALL track devices that broadcast BLE advertisements. Devices that only advertise when disconnected from their primary host (common for headphones) SHALL be handled gracefully: shown as "not visible" rather than removed.

### 3.2 Device List & Filtering

**FR-5** — The app SHALL maintain a persistent registry of known devices (ID, user-assigned name, device type icon).

**FR-6** — There SHALL be no cap on the number of registered or simultaneously tracked devices.

**FR-7** — Each registered device SHALL have a **tracking toggle**. Toggled-off devices are excluded from scanning callbacks processing and radar display but remain in the registry.

**FR-8** — The device list SHALL display live status per device: `visible` (with current smoothed distance), `not visible` (registered, not currently detected), `tracking off`.

### 3.3 Proximity Estimation

**FR-9** — Distance SHALL be estimated from RSSI using the log-distance path loss model:
`d = 10 ^ ((TxPower − RSSI) / (10 · n))`
where `TxPower` is the calibrated RSSI at 1 m (from advertisement data when present, else per-device-type default) and `n` is the environment factor (default 2.7, user-tunable in settings, range 2.0–4.0).

**FR-10** — Raw RSSI SHALL be smoothed before distance conversion using a 1-D Kalman filter (per device). Filter parameters are part of the spec: process noise `Q = 0.065`, measurement noise `R = 1.4` as starting defaults, tunable via config — these values MUST be injected, never hard-coded, so tests can control them.

**FR-11** — The UI SHALL present distance as both a numeric estimate (one decimal, meters) and a qualitative band:
- `immediate` — < 0.5 m
- `near` — 0.5–3 m
- `mid` — 3–10 m
- `far` — > 10 m
Band thresholds are config constants, injected.

**FR-12** — A device not seen for `T_stale = 10 s` (config) SHALL transition to `not visible`. Its radar blip fades out over 2 s.

### 3.4 Radar View

**FR-13** — The radar SHALL render concentric rings mapped to the qualitative bands (§FR-11), with the user's device at center.

**FR-14** — Each visible tracked device SHALL be rendered as a blip at radial distance proportional to smoothed distance (log-scaled so near-range differences are visually prominent).

**FR-15** — Blip angle SHALL be derived deterministically from the device ID (stable hash → angle), so blips do not jump between frames or sessions. Angle carries **no directional meaning** in v1 and the UI must not imply it does.

**FR-16** — A cosmetic sweep animation SHALL run continuously (target 60 fps; degrade gracefully).

**FR-17** — Tapping a blip SHALL open the device detail (name, raw RSSI, smoothed distance, band, last-seen).

### 3.5 Scanning Behavior

**FR-18** — Scanning SHALL be continuous while the app is foregrounded, on all platforms that permit it (Tier C: continuous RSSI polling of connected devices at 1 Hz minimum).

**FR-19** — Background behavior per tier: Tier A uses a foreground service (Android) or OS-native background scanning (desktop); Tier B accepts OS throttling and surfaces "updates paused/limited in background" state on resume; Tier C stops entirely when the tab is hidden.

---

## 4. Non-Functional Specification

**NFR-1 (Precision)** — Target accuracy with Kalman-smoothed RSSI: ±1 m at ranges ≤ 3 m, band-level accuracy beyond. This is the physical ceiling of RSSI ranging; the spec explicitly acknowledges it. Numeric display always accompanied by the band to set expectations.

**NFR-2 (Latency)** — Advertisement-to-radar-update ≤ 500 ms at p95 (foreground, Tier A/B).

**NFR-3 (Cold start)** — First device detection within 4 s of scan start (device advertising at ≥ 1 Hz, in range).

**NFR-4 (Battery)** — Continuous foreground scanning on Android SHALL use `SCAN_MODE_LOW_LATENCY` only while radar screen is visible; `SCAN_MODE_BALANCED` on the list screen. iOS equivalent: default CoreBluetooth scan with duplicates allowed only on radar screen.

**NFR-5 (Rendering)** — Radar animation SHALL not drop below 30 fps with 50 simultaneous blips on a mid-range 2023 device.

**NFR-6 (Robustness)** — BLE adapter off / permission revoked mid-session SHALL surface a recoverable UI state, never a crash. All adapter state transitions are part of the state machine spec (§5.4).

---

## 5. Architecture & Interface Contracts

Layered architecture; every boundary is an abstract class (Dart `abstract interface class`) defined **before** implementation. UI depends on state; state depends on domain interfaces; platform plugins are hidden behind those interfaces.

```
ui/ (widgets, radar painter)
        │
state/ (Riverpod providers, view models)
        │
domain/ (pure logic: filtering, distance, registry rules)
        │
platform/ (BLE plugin adapters, persistence adapters)
```

### 5.1 Domain Interfaces

```dart
/// Emits raw scan observations. Implemented per platform tier.
abstract interface class BleScanner {
  Stream<ScanObservation> observe();          // never errors; state via ScannerStatus
  Stream<ScannerStatus> status();             // idle / scanning / unavailable / unauthorized
  Future<void> start(ScanProfile profile);    // profile: lowLatency | balanced
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
```

### 5.2 Platform Abstraction

```dart
abstract interface class PlatformCapabilities {
  CapabilityTier get tier;                    // tierA | tierB | tierC
  bool get supportsAutoDiscovery;
  bool get supportsBackgroundScan;
}
```

One `BleScanner` implementation per underlying mechanism:
- `FlutterBluePlusScanner` (Android, iOS, macOS, Windows — via flutter_blue_plus)
- `BlueZScanner` (Linux — via bluez package or FFI)
- `WebBluetoothScanner` (Web — connected-device RSSI polling)
- `WearScanner` (Wear OS — Android scanner with Wear lifecycle constraints)

Each adapter is thin: translate plugin events → `ScanObservation`. All logic lives above the boundary where it is testable.

### 5.3 Core Data Types

```dart
class ScanObservation {
  final String deviceId;
  final double rssi;
  final double? txPower;        // from advertisement, nullable
  final DateTime timestamp;
  final String? advertisedName;
}

class DistanceEstimate {
  final double meters;
  final ProximityBand band;     // immediate | near | mid | far
}

class TrackedDeviceState {
  final RegisteredDevice device;
  final DeviceVisibility visibility;   // visible | notVisible | trackingOff
  final DistanceEstimate? estimate;    // null unless visible
  final DateTime? lastSeen;
}
```

### 5.4 Scanner State Machine

`ScannerStatus` transitions (spec'd so NFR-6 is testable):

```
idle ──start()──▶ scanning
scanning ──stop()──▶ idle
scanning ──adapterOff──▶ unavailable ──adapterOn──▶ scanning (auto-resume)
any ──permissionRevoked──▶ unauthorized ──permissionGranted + start()──▶ scanning
```

Every transition above MUST have a corresponding unit test against a mock scanner.

---

## 6. State Management

- **Riverpod** with code-gen providers.
- `deviceStatesProvider` — `Stream<Map<String, TrackedDeviceState>>` — the single source of truth composing: registry stream × scan observations × smoothing × staleness ticker.
- Staleness (`FR-12`) driven by an injected `Clock`/ticker so tests control time — no real timers in domain logic.
- All providers take interfaces, never concrete platform classes.

---

## 7. Test Plan

### 7.1 Principles

- **No integration tests** (no hardware rig available). The gap is covered by (a) maximal unit coverage of all logic, (b) contract tests every `BleScanner` adapter must pass against a shared test suite, (c) a written manual test checklist (§7.5) executed per release.
- Coverage target: **100% of domain/ and state/**; platform adapters covered to the extent mockable (plugin call translation), UI via widget + golden tests.
- Every FR/NFR that is logic-expressible maps to at least one named test.

### 7.2 Unit Tests (pure logic — the bulk of coverage)

| Module | Test focus |
|---|---|
| `RssiSmoother` (Kalman) | convergence on constant signal; jitter attenuation ratio; step-response lag; per-device isolation; reset behavior; parameter injection |
| `DistanceEstimator` | known RSSI/TxPower/n triples → expected meters (table-driven); band boundary values (exactly 0.5, 3.0, 10.0 m); missing TxPower fallback |
| `RadarLayout.angleFor` | determinism (same id → same angle across calls); distribution sanity (no clustering for sequential ids); stability across sessions |
| `RadarLayout.radiusFor` | log-scaling monotonicity; clamping at band edges; [0,1] bounds |
| Staleness logic | visible → notVisible at exactly T_stale via fake clock; re-acquisition resets timer |
| Registry rules | toggle-off excludes from state composition; rename/remove propagation; no-cap behavior (property test with 1 000 devices) |
| Scanner state machine | every transition in §5.4; illegal transitions rejected |

### 7.3 Contract Tests

A shared `BleScannerContract` test suite (Given a fake plugin backend: start emits scanning status; observations map fields correctly; adapter-off mid-scan → unavailable; stop is idempotent). Every adapter implementation runs the identical suite with its own fake backend.

### 7.4 Widget & Golden Tests

- Radar view: pump a fixed `Map<String, TrackedDeviceState>` → golden image per band configuration; blip fade-out animation frames; tap-target hit testing on blips.
- Device list: all three visibility states render; toggle dispatches `setTracking`.
- Tier-adaptive UI: Tier C hides auto-discover affordances; unsupported-browser message renders.

### 7.5 Manual Test Checklist (per release, replaces integration tests)

1. Android + iOS: register headphones, verify band transitions walking away/toward.
2. Adapter off/on mid-session on each mobile platform → recoverable UI.
3. Permission revoke mid-session (Android) → unauthorized state, re-grant recovers.
4. Web (Chrome): manual pair, RSSI polling updates radar; Safari shows unsupported message.
5. Wear OS: foreground tracking of one device; background resume shows paused-state notice.
6. 20+ simultaneous devices on Android: radar remains ≥ 30 fps (visual check + DevTools).

### 7.6 CI

- `flutter analyze` (strict lints, no warnings) + `flutter test --coverage` on every PR.
- Coverage gate: fail below 100% on `domain/` and `state/` paths.
- Golden tests run on a pinned renderer to avoid cross-machine diffs.

---

## 8. SDD Workflow

For each module, in order:

1. Write/refine the interface + data types in this spec (PR to spec doc).
2. Write the failing test suite against the interface.
3. Implement until green; refactor.
4. Update the traceability table (§8.1).

### 8.1 Traceability (maintained as modules land)

| Requirement | Interface(s) | Test suite |
|---|---|---|
| FR-9, FR-10, NFR-1 | RssiSmoother, DistanceEstimator | rssi_smoother_test, distance_estimator_test |
| FR-11 | DistanceEstimator | band_boundaries_test |
| FR-12 | state composition + Clock | staleness_test |
| FR-13–FR-16 | RadarLayout, RadarPainter | radar_layout_test, radar_golden_test |
| FR-5–FR-8 | DeviceRegistry | registry_test |
| NFR-6, §5.4 | BleScanner status | scanner_state_machine_test, contract suites |

---

## 9. Future Enhancements (explicitly out of v1)

- **UWB precision ranging + true bearing** (iPhone 11+/Nearby Interaction, Android UWB API on supported flagships) — would replace pseudo-angles with real angle-of-arrival on capable hardware; requires platform channels (no mature Flutter plugin).
- Out-of-range alerts with configurable thresholds.
- Last-seen history & map integration.
- Companion web dashboard consuming state from a mobile node (works around Tier C limits).

---

## 10. Open Questions

- **OQ-1:** Persistence backend for `DeviceRegistry` — `shared_preferences` (simple, sufficient for a registry) vs `drift` (if history lands later). Proposal: shared_preferences now, interface makes swapping trivial.
- **OQ-2:** Linux BLE — `bluez` Dart package vs FFI to BlueZ D-Bus. Needs a spike.
- **OQ-3:** Should environment factor `n` (§FR-9) be per-device rather than global? Per-device calibration ("stand 1 m away and tap calibrate") would meaningfully improve NFR-1.
