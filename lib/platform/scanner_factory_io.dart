import 'dart:io';

import 'package:bluez/bluez.dart';

import '../domain/interfaces.dart';
import 'bluez/bluez_api_impl.dart';
import 'bluez/bluez_scanner.dart';
import 'fbp/fbp_api_impl.dart';
import 'fbp/flutter_blue_plus_scanner.dart';
import 'wear/wear_scanner.dart';

/// Non-web factory: Linux talks to BlueZ directly over D-Bus (OQ-2 —
/// package:bluez rather than platform-channel FFI); every other native
/// platform (Android/iOS/macOS/Windows) goes through flutter_blue_plus.
/// A Wear OS build additionally wraps the result in [WearScanner].
Future<BleScanner> createScanner(
    PlatformCapabilities caps, Stream<DateTime> ticks) async {
  final BleScanner base =
      Platform.isLinux ? await _blueZScanner() : FlutterBluePlusScanner(FbpApiImpl());
  if (const bool.fromEnvironment('WEAR_OS')) {
    // Ambient (watch-face-visible) detection is wired via a real plugin
    // stream (e.g. flutter_wear_os_connectivity) in the Wear OS flavor's
    // own bootstrap; a stream that never fires is functionally correct
    // here too — WearScanner just never downgrades to balanced (FR-19).
    return WearScanner(inner: base, isAmbient: const Stream<bool>.empty());
  }
  return base;
}

Future<BleScanner> _blueZScanner() async {
  final client = BlueZClient();
  // BlueZScanner's constructor subscribes to BlueZApiImpl.adapterOn()
  // immediately, which reads _client.adapters.first — that list is only
  // populated after the object-manager handshake in BlueZClient.connect().
  // Must await here, before constructing the scanner, or the constructor
  // throws on an empty adapter list.
  await client.connect();
  return BlueZScanner(BlueZApiImpl(client));
}
