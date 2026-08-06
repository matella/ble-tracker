// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(proximityConfig)
final proximityConfigProvider = ProximityConfigProvider._();

final class ProximityConfigProvider
    extends
        $FunctionalProvider<ProximityConfig, ProximityConfig, ProximityConfig>
    with $Provider<ProximityConfig> {
  ProximityConfigProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proximityConfigProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proximityConfigHash();

  @$internal
  @override
  $ProviderElement<ProximityConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProximityConfig create(Ref ref) {
    return proximityConfig(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProximityConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProximityConfig>(value),
    );
  }
}

String _$proximityConfigHash() => r'c723dfb13f3815e065ea51c5f07a115369f8cc39';

@ProviderFor(bleScanner)
final bleScannerProvider = BleScannerProvider._();

final class BleScannerProvider
    extends $FunctionalProvider<BleScanner, BleScanner, BleScanner>
    with $Provider<BleScanner> {
  BleScannerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bleScannerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bleScannerHash();

  @$internal
  @override
  $ProviderElement<BleScanner> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BleScanner create(Ref ref) {
    return bleScanner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BleScanner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BleScanner>(value),
    );
  }
}

String _$bleScannerHash() => r'559d2d8b0b8fd7d81d116737bd885a973cb3df59';

@ProviderFor(deviceRegistry)
final deviceRegistryProvider = DeviceRegistryProvider._();

final class DeviceRegistryProvider
    extends $FunctionalProvider<DeviceRegistry, DeviceRegistry, DeviceRegistry>
    with $Provider<DeviceRegistry> {
  DeviceRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceRegistryHash();

  @$internal
  @override
  $ProviderElement<DeviceRegistry> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeviceRegistry create(Ref ref) {
    return deviceRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceRegistry>(value),
    );
  }
}

String _$deviceRegistryHash() => r'5f71cbf9dc4637252d939d9fa0131725753bc8b3';

@ProviderFor(platformCapabilities)
final platformCapabilitiesProvider = PlatformCapabilitiesProvider._();

final class PlatformCapabilitiesProvider
    extends
        $FunctionalProvider<
          PlatformCapabilities,
          PlatformCapabilities,
          PlatformCapabilities
        >
    with $Provider<PlatformCapabilities> {
  PlatformCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'platformCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$platformCapabilitiesHash();

  @$internal
  @override
  $ProviderElement<PlatformCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlatformCapabilities create(Ref ref) {
    return platformCapabilities(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlatformCapabilities value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlatformCapabilities>(value),
    );
  }
}

String _$platformCapabilitiesHash() =>
    r'377376303bb2409bdb54124ec9b8e8ded4e9a01d';

@ProviderFor(ticker)
final tickerProvider = TickerProvider._();

final class TickerProvider
    extends
        $FunctionalProvider<
          Raw<Stream<DateTime>>,
          Raw<Stream<DateTime>>,
          Raw<Stream<DateTime>>
        >
    with $Provider<Raw<Stream<DateTime>>> {
  TickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tickerHash();

  @$internal
  @override
  $ProviderElement<Raw<Stream<DateTime>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Raw<Stream<DateTime>> create(Ref ref) {
    return ticker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Raw<Stream<DateTime>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Raw<Stream<DateTime>>>(value),
    );
  }
}

String _$tickerHash() => r'82d4ba6cd549ae33905b3fcfe9186ac7c76a545d';

@ProviderFor(rssiSmoother)
final rssiSmootherProvider = RssiSmootherProvider._();

final class RssiSmootherProvider
    extends $FunctionalProvider<RssiSmoother, RssiSmoother, RssiSmoother>
    with $Provider<RssiSmoother> {
  RssiSmootherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rssiSmootherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rssiSmootherHash();

  @$internal
  @override
  $ProviderElement<RssiSmoother> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RssiSmoother create(Ref ref) {
    return rssiSmoother(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RssiSmoother value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RssiSmoother>(value),
    );
  }
}

String _$rssiSmootherHash() => r'd5f18460b630fd73547d8c77feba3115c1aa2fe0';

@ProviderFor(distanceEstimator)
final distanceEstimatorProvider = DistanceEstimatorProvider._();

final class DistanceEstimatorProvider
    extends
        $FunctionalProvider<
          DistanceEstimator,
          DistanceEstimator,
          DistanceEstimator
        >
    with $Provider<DistanceEstimator> {
  DistanceEstimatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'distanceEstimatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$distanceEstimatorHash();

  @$internal
  @override
  $ProviderElement<DistanceEstimator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DistanceEstimator create(Ref ref) {
    return distanceEstimator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DistanceEstimator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DistanceEstimator>(value),
    );
  }
}

String _$distanceEstimatorHash() => r'00eda9335fd91885dd1521ee539cc9c72ad354b5';

@ProviderFor(radarLayout)
final radarLayoutProvider = RadarLayoutProvider._();

final class RadarLayoutProvider
    extends $FunctionalProvider<RadarLayout, RadarLayout, RadarLayout>
    with $Provider<RadarLayout> {
  RadarLayoutProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'radarLayoutProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$radarLayoutHash();

  @$internal
  @override
  $ProviderElement<RadarLayout> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RadarLayout create(Ref ref) {
    return radarLayout(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RadarLayout value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RadarLayout>(value),
    );
  }
}

String _$radarLayoutHash() => r'ad7e37ebdd1c0ed5cd2176e8b4dd25e63ef89f80';

@ProviderFor(scannerStatus)
final scannerStatusProvider = ScannerStatusProvider._();

final class ScannerStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScannerStatus>,
          ScannerStatus,
          Stream<ScannerStatus>
        >
    with $FutureModifier<ScannerStatus>, $StreamProvider<ScannerStatus> {
  ScannerStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scannerStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scannerStatusHash();

  @$internal
  @override
  $StreamProviderElement<ScannerStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ScannerStatus> create(Ref ref) {
    return scannerStatus(ref);
  }
}

String _$scannerStatusHash() => r'85673d1cddfcae0ade3f51f86f87722f7295bb96';

@ProviderFor(deviceStates)
final deviceStatesProvider = DeviceStatesProvider._();

final class DeviceStatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, TrackedDeviceState>>,
          Map<String, TrackedDeviceState>,
          Stream<Map<String, TrackedDeviceState>>
        >
    with
        $FutureModifier<Map<String, TrackedDeviceState>>,
        $StreamProvider<Map<String, TrackedDeviceState>> {
  DeviceStatesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceStatesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceStatesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, TrackedDeviceState>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, TrackedDeviceState>> create(Ref ref) {
    return deviceStates(ref);
  }
}

String _$deviceStatesHash() => r'3ca3a09d98e14e5037453aaf5f10a371880dd0ef';

/// FR-17: raw RSSI per device, for the device detail sheet.

@ProviderFor(latestRssi)
final latestRssiProvider = LatestRssiProvider._();

/// FR-17: raw RSSI per device, for the device detail sheet.

final class LatestRssiProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, double>>,
          Map<String, double>,
          Stream<Map<String, double>>
        >
    with
        $FutureModifier<Map<String, double>>,
        $StreamProvider<Map<String, double>> {
  /// FR-17: raw RSSI per device, for the device detail sheet.
  LatestRssiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'latestRssiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$latestRssiHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, double>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, double>> create(Ref ref) {
    return latestRssi(ref);
  }
}

String _$latestRssiHash() => r'811ce3f46abe8ec9d511d3694d7fe12206311029';
