import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';
import 'scanner_status_banner.dart';

class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(deviceStatesProvider).value ?? {};
    final caps = ref.watch(platformCapabilitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Column(
        children: [
          const ScannerStatusBanner(),
          if (caps.supportsAutoDiscovery)
            const ListTile(
              key: Key('auto-discover-note'),
              leading: Icon(Icons.radar),
              title: Text('Known devices are re-acquired automatically.'),
            )
          else
            ListTile(
              key: const Key('manual-pair-button'),
              leading: const Icon(Icons.add_link),
              title: const Text('Pair a device'),
              subtitle: const Text(
                  'This browser only supports manually paired devices.'),
              onTap: () {
                // Wired to WebBluetoothScanner.pairNewDevice in Task 19.
              },
            ),
          Expanded(
            child: ListView(
              children: [
                for (final s in states.values)
                  ListTile(
                    leading: Icon(_iconFor(s.device.type)),
                    title: Text(s.device.name),
                    subtitle: Text(_statusLine(s)),
                    trailing: Switch(
                      key: Key('tracking-toggle-${s.device.id}'),
                      value: s.device.trackingEnabled,
                      onChanged: (v) => ref
                          .read(deviceRegistryProvider)
                          .setTracking(s.device.id, v),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(DeviceType type) => switch (type) {
        DeviceType.headphones => Icons.headphones,
        DeviceType.phone => Icons.smartphone,
        DeviceType.tag => Icons.sell,
        DeviceType.watch => Icons.watch,
        DeviceType.other => Icons.bluetooth,
      };

  String _statusLine(TrackedDeviceState s) => switch (s.visibility) {
        DeviceVisibility.visible =>
          '${s.estimate!.meters.toStringAsFixed(1)} m · ${s.estimate!.band.name}',
        DeviceVisibility.notVisible => 'Not visible',
        DeviceVisibility.trackingOff => 'Tracking off',
      };
}
