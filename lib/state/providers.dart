import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/config.dart';
import '../domain/hash_radar_layout.dart';
import '../domain/interfaces.dart';
import '../domain/kalman_rssi_smoother.dart';
import '../domain/key_value_store.dart';
import '../domain/log_distance_estimator.dart';
import '../domain/manual_pairing.dart';
import '../domain/settings.dart';
import '../domain/types.dart';
import 'device_state_composer.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
KeyValueStore settingsStore(Ref ref) =>
    throw UnimplementedError('override with the app store in main()');

/// The environment factor read from storage before the first frame (main()
/// parses it with [parseEnvironmentFactor], so this is always valid).
@Riverpod(keepAlive: true)
double initialEnvironmentFactor(Ref ref) => defaultEnvironmentFactor;

/// FR-9: user-tunable path-loss exponent `n`. Changing it rebuilds the config,
/// which rebuilds the composer: smoothing restarts and devices show as not
/// visible until each is heard again.
@Riverpod(keepAlive: true)
class EnvironmentFactor extends _$EnvironmentFactor {
  @override
  double build() => ref.watch(initialEnvironmentFactorProvider);

  Future<void> set(double value) async {
    state = value;
    try {
      await ref
          .read(settingsStoreProvider)
          .write(environmentFactorStorageKey, value.toString());
    } on Object catch (error) {
      // The new value still applies for this session; it just will not
      // survive a restart.
      debugPrint('EnvironmentFactor: not persisted: $error');
    }
  }
}

/// FR-19 Tier A: keeps scanning alive in the background. Overridden in main()
/// with the Android foreground service on Android; a no-op everywhere else.
@Riverpod(keepAlive: true)
BackgroundScanHost backgroundScanHost(Ref ref) =>
    const NoopBackgroundScanHost();

/// FR-19 Tier B: true from the moment the app returns from the background
/// until the next scan observation confirms updates are flowing again.
@Riverpod(keepAlive: true)
class ResumeNotice extends _$ResumeNotice {
  @override
  bool build() => false;

  void show() => state = true;

  void clear() => state = false;
}

@Riverpod(keepAlive: true)
ProximityConfig proximityConfig(Ref ref) =>
    ProximityConfig(environmentFactor: ref.watch(environmentFactorProvider));

@Riverpod(keepAlive: true)
BleScanner bleScanner(Ref ref) =>
    throw UnimplementedError('override with a platform scanner in main()');

/// Tier C manual-pairing entry point (FR-3), when the active scanner exposes
/// one. Null for every other tier — the UI only wires the pair button when
/// this is non-null.
@Riverpod(keepAlive: true)
ManualPairing? manualPairing(Ref ref) {
  final scanner = ref.watch(bleScannerProvider);
  return scanner is ManualPairing ? scanner as ManualPairing : null;
}

@Riverpod(keepAlive: true)
DeviceRegistry deviceRegistry(Ref ref) =>
    throw UnimplementedError('override with a persistent registry in main()');

@Riverpod(keepAlive: true)
PlatformCapabilities platformCapabilities(Ref ref) =>
    throw UnimplementedError('override with detected capabilities in main()');

// Raw<> tells riverpod_generator to hand back the plain Stream<DateTime>
// instead of wrapping it in an AsyncValue, so the composer below receives
// the stream synchronously (see task-10-brief.md note on tickerProvider).
@Riverpod(keepAlive: true)
Raw<Stream<DateTime>> ticker(Ref ref) =>
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
Stream<ScannerStatus> scannerStatus(Ref ref) =>
    ref.watch(bleScannerProvider).status();

@Riverpod(keepAlive: true)
Stream<Map<String, TrackedDeviceState>> deviceStates(Ref ref) {
  final composer = DeviceStateComposer(
    registry: ref.watch(deviceRegistryProvider).watchAll(),
    observations: ref.watch(bleScannerProvider).observe(),
    ticks: ref.watch(tickerProvider),
    smoother: ref.watch(rssiSmootherProvider),
    estimator: ref.watch(distanceEstimatorProvider),
    config: ref.watch(proximityConfigProvider),
  );
  ref.onDispose(composer.dispose);
  return composer.states;
}

/// FR-17: raw RSSI per device, for the device detail sheet.
@Riverpod(keepAlive: true)
Stream<Map<String, double>> latestRssi(Ref ref) async* {
  final latest = <String, double>{};
  await for (final obs in ref.watch(bleScannerProvider).observe()) {
    latest[obs.deviceId] = obs.rssi;
    yield Map.of(latest);
  }
}

/// FR-1: raw scan observations for the discovery screen (manual "track this
/// device" flow), independent of registration status.
@Riverpod(keepAlive: true)
Stream<ScanObservation> discoveryObservations(Ref ref) =>
    ref.watch(bleScannerProvider).observe();
