import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';
import 'device_list_screen.dart';
import 'discovery_screen.dart';
import 'radar_screen.dart';

/// App shell: owns the scan lifecycle (NFR-4 — lowLatency on the radar tab,
/// balanced elsewhere) so individual screens don't each start their own
/// scan.
class BleTrackerApp extends ConsumerStatefulWidget {
  const BleTrackerApp({super.key});

  @override
  ConsumerState<BleTrackerApp> createState() => _BleTrackerAppState();
}

class _BleTrackerAppState extends ConsumerState<BleTrackerApp> {
  int _tab = 0;
  // FR-19 Tier C: scanning stops entirely while the browser tab is hidden.
  // On web, AppLifecycleState.hidden is the "tab no longer visible" signal.
  late final AppLifecycleListener _lifecycle;
  bool _pausedByVisibility = false;

  static const _profiles = [
    ScanProfile.lowLatency, // radar (NFR-4)
    ScanProfile.balanced, // device list
    ScanProfile.balanced, // discovery
  ];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _onHidden, onShow: _onShown);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleScannerProvider).start(_profiles[_tab]);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  bool get _isTierC =>
      ref.read(platformCapabilitiesProvider).tier == CapabilityTier.tierC;

  void _onHidden() {
    if (!_isTierC) return;
    // Only resume what this visibility change stopped: a scanner that was
    // already idle or unauthorized must not be started later by mistake.
    if (ref.read(scannerStatusProvider).value != ScannerStatus.scanning) {
      return;
    }
    _pausedByVisibility = true;
    ref
        .read(bleScannerProvider)
        .stop()
        .catchError((Object e) => debugPrint('visibility stop failed: $e'));
  }

  void _onShown() {
    if (!_pausedByVisibility) return;
    _pausedByVisibility = false;
    ref
        .read(bleScannerProvider)
        .start(_profiles[_tab])
        .catchError((Object e) => debugPrint('visibility start failed: $e'));
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    // Only cycle the scanner when it's in a state where stop()+start()
    // means something (scanning with the old profile, or idle before the
    // first scan starts). Doing this unconditionally while unavailable or
    // unauthorized would fight the recoverable-state banner: stop() is a
    // no-op there and start() can throw/queue a transition that has
    // nothing to do with the tab switch. The tab UI still switches either
    // way — only the scan lifecycle is guarded.
    final status = ref.read(scannerStatusProvider).value;
    if (status == ScannerStatus.scanning || status == ScannerStatus.idle) {
      final scanner = ref.read(bleScannerProvider);
      scanner.stop().then((_) => scanner.start(_profiles[i])).catchError(
          (Object e) => debugPrint('scan restart failed: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Tracker',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: const [RadarScreen(), DeviceListScreen(), DiscoveryScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
            NavigationDestination(
                icon: Icon(Icons.devices), label: 'Devices'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Discover'),
          ],
        ),
      ),
    );
  }
}
