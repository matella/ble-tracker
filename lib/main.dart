import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/interfaces.dart';
import 'domain/persistent_device_registry.dart';
import 'platform/default_platform_capabilities.dart';
import 'platform/scanner_factory_io.dart'
    if (dart.library.js_interop) 'platform/scanner_factory_web.dart';
import 'platform/shared_prefs_store.dart';
import 'platform/unavailable_ble_scanner.dart';
import 'state/providers.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final caps = DefaultPlatformCapabilities(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
    isWatch: const bool.fromEnvironment('WEAR_OS'),
  );
  // Broadcast: shared between the deviceStates composer (always) and, on
  // Tier C, WebBluetoothScanner's RSSI poll loop (see scanner_factory_web).
  // Stream.periodic is single-subscription by default and would throw on
  // the second listener otherwise.
  final ticks = Stream<DateTime>.periodic(
      const Duration(seconds: 1), (_) => DateTime.now()).asBroadcastStream();
  late final BleScanner scanner;
  try {
    scanner = await createScanner(caps, ticks);
  } on Object catch (error) {
    // Real scanner init failed (e.g. BlueZ D-Bus unreachable): run degraded
    // rather than crashing before any UI exists (NFR-6).
    debugPrint('BLE scanner init failed, running degraded: $error');
    scanner = UnavailableBleScanner();
  }
  runApp(ProviderScope(
    overrides: [
      bleScannerProvider.overrideWithValue(scanner),
      deviceRegistryProvider
          .overrideWithValue(PersistentDeviceRegistry(SharedPrefsStore())),
      platformCapabilitiesProvider.overrideWithValue(caps),
      tickerProvider.overrideWithValue(ticks),
    ],
    child: const BleTrackerApp(),
  ));
}
