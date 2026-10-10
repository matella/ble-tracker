import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/interfaces.dart';
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
  bool _hiddenSinceShown = false;

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

  bool get _isTierB =>
      ref.read(platformCapabilitiesProvider).tier == CapabilityTier.tierB;

  /// #32: while backgrounded, Android scans only the registered devices, so
  /// results keep arriving with the screen off. Foreground scans are
  /// unfiltered (Discover needs everything).
  void _applyBackgroundFilter({required bool background}) {
    final scanner = ref.read(bleScannerProvider);
    final caps = ref.read(platformCapabilitiesProvider);
    if (scanner is! RemoteIdFilterable ||
        !caps.supportsBackgroundScan ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final ids = background
        ? (ref.read(deviceStatesProvider).value?.keys.toSet() ?? <String>{})
        : <String>{};
    (scanner as RemoteIdFilterable)
        .setRemoteIdFilter(ids)
        .catchError((Object e) => debugPrint('remote-id filter: $e'));
  }

  void _onHidden() {
    _hiddenSinceShown = true;
    _applyBackgroundFilter(background: true);
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
    final wasHidden = _hiddenSinceShown;
    _hiddenSinceShown = false;
    _applyBackgroundFilter(background: false);
    // FR-19 Tier B: the OS throttled scanning while we were away. Say so until
    // the next observation proves updates are flowing again.
    if (wasHidden && _isTierB) {
      ref.read(resumeNoticeProvider.notifier).show();
    }
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
    // The first scan result after a resume means updates are flowing again.
    ref.listen(discoveryObservationsProvider, (_, next) {
      if (next.hasValue) ref.read(resumeNoticeProvider.notifier).clear();
    });
    // FR-19 Tier A: the background service runs only while scanning, and only
    // on tiers that declare background scanning (Wear and web never do).
    ref.listen(scannerStatusProvider, (_, next) {
      if (!ref.read(platformCapabilitiesProvider).supportsBackgroundScan) {
        return;
      }
      final scanning = next.value == ScannerStatus.scanning;
      ref
          .read(backgroundScanHostProvider)
          .setActive(scanning)
          .catchError((Object e) => debugPrint('background scan: $e'));
    });
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
