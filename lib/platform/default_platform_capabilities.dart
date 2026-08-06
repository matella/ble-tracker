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
