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
  ProximityConfig config, {
  Map<String, double> lastKnownRadius = const {},
}) {
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
          radius: lastKnownRadius[s.device.id] ?? 1,
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
