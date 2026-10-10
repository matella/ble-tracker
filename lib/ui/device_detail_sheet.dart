import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// FR-17: name, raw RSSI, smoothed distance, band, last-seen.
class DeviceDetailSheet extends ConsumerWidget {
  const DeviceDetailSheet({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceStatesProvider).value?[deviceId];
    final rssi = ref.watch(latestRssiProvider).value?[deviceId];
    if (state == null) return const SizedBox.shrink();
    final e = state.estimate;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.device.name,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Raw RSSI: ${rssi?.toStringAsFixed(0) ?? '—'} dBm'),
          Text(e == null
              ? 'Distance: —'
              : 'Distance: ${e.meters.toStringAsFixed(1)} m (${e.band.name})'),
          Text('Last seen: ${formatLastSeen(state.lastSeen)}'),
        ],
      ),
    );
  }
}

/// Local time as `yyyy-MM-dd HH:mm:ss`, or `never`. Absolute on purpose: a
/// relative "5 s ago" would need a current time, and time is injected here.
@visibleForTesting
String formatLastSeen(DateTime? time) {
  if (time == null) return 'never';
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
