import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/interfaces.dart';
import 'domain/key_value_store.dart';
import 'domain/persistent_device_registry.dart';
import 'domain/settings.dart';
import 'platform/android/background_scan_host.dart';
import 'platform/default_platform_capabilities.dart';
import 'platform/scanner_factory_io.dart'
    if (dart.library.js_interop) 'platform/scanner_factory_web.dart';
import 'platform/shared_prefs_store.dart';
import 'platform/unavailable_ble_scanner.dart';
import 'state/providers.dart';
import 'ui/app.dart';

Future<String?> _readOrNull(KeyValueStore store, String key) async {
  try {
    return await store.read(key);
  } on Object catch (error) {
    debugPrint('settings: could not read $key, using default: $error');
    return null;
  }
}

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
  final store = SharedPrefsStore();
  // Read before the first frame so the config is right from the start. A
  // storage failure here falls back to the default rather than blocking launch.
  final environmentFactor = parseEnvironmentFactor(await _readOrNull(
      store, environmentFactorStorageKey));
  runApp(ProviderScope(
    overrides: [
      bleScannerProvider.overrideWithValue(scanner),
      deviceRegistryProvider.overrideWithValue(PersistentDeviceRegistry(store)),
      platformCapabilitiesProvider.overrideWithValue(caps),
      tickerProvider.overrideWithValue(ticks),
      // Tier A Android only. Web is Tier C and Wear is Tier B, so both fall
      // through to the no-op.
      backgroundScanHostProvider.overrideWithValue(
        caps.supportsBackgroundScan && defaultTargetPlatform == TargetPlatform.android
            ? AndroidBackgroundScanHost()
            : const NoopBackgroundScanHost(),
      ),
      settingsStoreProvider.overrideWithValue(store),
      initialEnvironmentFactorProvider.overrideWithValue(environmentFactor),
    ],
    child: const BleTrackerApp(),
  ));
}
