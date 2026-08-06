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
      final previous = _devices[d.id];
      _devices[d.id] = d;
      if (!d.trackingEnabled) {
        _visibility[d.id] = DeviceVisibility.trackingOff;
      } else if (previous == null || !previous.trackingEnabled) {
        // New or re-enabled device: notVisible until an observation arrives.
        _visibility[d.id] = DeviceVisibility.notVisible;
      }
      // Otherwise keep current visibility — staleness must not be undone by
      // unrelated registry emissions (FR-12).
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
