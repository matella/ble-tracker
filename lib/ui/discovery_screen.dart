import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';

/// FR-1: scan results the user can register. Observations from devices not
/// yet in the registry are listed here with a Track button.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final Map<String, ScanObservation> _seen = {};
  StreamSubscription<DateTime>? _tickSub;

  @override
  void initState() {
    super.initState();
    // Injected time (CLAUDE.md invariant): prune via the ticker, not the wall
    // clock, so a device that stops advertising drops off the list.
    _tickSub = ref.read(tickerProvider).listen(_prune);
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    super.dispose();
  }

  void _prune(DateTime now) {
    final staleAfter = ref.read(proximityConfigProvider).staleAfter;
    final before = _seen.length;
    _seen.removeWhere((_, o) => now.difference(o.timestamp) >= staleAfter);
    if (_seen.length != before) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(discoveryObservationsProvider, (_, next) {
      next.whenData((obs) => setState(() => _seen[obs.deviceId] = obs));
    });
    final registered =
        ref.watch(deviceStatesProvider).value?.keys.toSet() ?? {};
    final unregistered =
        _seen.values.where((o) => !registered.contains(o.deviceId)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: ListView(
        children: [
          for (final o in unregistered)
            ListTile(
              key: ValueKey('discovered-${o.deviceId}'),
              leading: const Icon(Icons.bluetooth_searching),
              title: Text(o.advertisedName ?? o.deviceId),
              subtitle: Text('${o.rssi.toStringAsFixed(0)} dBm'),
              trailing: FilledButton(
                child: const Text('Track'),
                onPressed: () => ref.read(deviceRegistryProvider).register(
                      RegisteredDevice(
                        id: o.deviceId,
                        name: o.advertisedName ?? o.deviceId,
                        type: DeviceType.other,
                      ),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
