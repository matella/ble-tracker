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
