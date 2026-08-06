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

  test('unclassified platform falls back to Tier B, not Tier A', () {
    final c = caps(TargetPlatform.fuchsia);
    expect(c.tier, CapabilityTier.tierB);
    expect(c.supportsAutoDiscovery, isTrue);
    expect(c.supportsBackgroundScan, isFalse);
  });
}
