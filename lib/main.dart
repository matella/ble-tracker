import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/interfaces.dart';
import 'domain/persistent_device_registry.dart';
import 'platform/default_platform_capabilities.dart';
import 'platform/scanner_factory_io.dart'
    if (dart.library.js_interop) 'platform/scanner_factory_web.dart';
import 'platform/shared_prefs_store.dart';
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
  final BleScanner scanner = await createScanner(caps, ticks);
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
