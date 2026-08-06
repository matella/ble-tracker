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
    final states = ref.watch(deviceStatesProvider).value ?? {};
    final layout = ref.watch(radarLayoutProvider);
    final config = ref.watch(proximityConfigProvider);
    // Keep the raw-RSSI stream subscribed from screen mount (not just when
    // the detail sheet opens) so it isn't missing observations emitted
    // before a tap — bleScannerProvider.observe() is a broadcast stream
    // with no replay for late subscribers.
    ref.watch(latestRssiProvider);

    // FR-13: rings map to band boundaries under the log mapping.
    final ringRadii = [
      layout.radiusFor(DistanceEstimate(
          meters: config.immediateMaxMeters,
          band: ProximityBand.immediate)),
      layout.radiusFor(DistanceEstimate(
          meters: config.nearMaxMeters, band: ProximityBand.near)),
      layout.radiusFor(
          DistanceEstimate(meters: config.midMaxMeters, band: ProximityBand.mid)),
      1.0,
    ];

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
                          ringRadii: ringRadii,
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
