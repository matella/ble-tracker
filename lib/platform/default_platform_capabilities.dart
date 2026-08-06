import 'package:flutter/foundation.dart';

import '../domain/interfaces.dart';
import '../domain/types.dart';

class DefaultPlatformCapabilities implements PlatformCapabilities {
  static const Set<TargetPlatform> _tierAPlatforms = {
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  };

  DefaultPlatformCapabilities({
    required TargetPlatform platform,
    required bool isWeb,
    bool isWatch = false,
  }) : tier = isWeb
            ? CapabilityTier.tierC
            : (platform == TargetPlatform.iOS || isWatch)
                ? CapabilityTier.tierB
                : _tierAPlatforms.contains(platform)
                    ? CapabilityTier.tierA
                    // Unclassified platforms get reduced capability rather than
                    // silently inheriting full background scanning (spec §2 only
                    // enumerates the four Tier A platforms).
                    : CapabilityTier.tierB;

  @override
  final CapabilityTier tier;

  @override
  bool get supportsAutoDiscovery => tier != CapabilityTier.tierC;

  @override
  bool get supportsBackgroundScan => tier == CapabilityTier.tierA;
}
