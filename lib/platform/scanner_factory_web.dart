import '../domain/interfaces.dart';
import 'web/web_bluetooth_api_impl.dart';
import 'web/web_bluetooth_scanner.dart';

/// Web factory (Tier C): no advertisement scanning API, so RSSI is polled
/// for manually-paired devices on every injected tick (FR-18).
Future<BleScanner> createScanner(
        PlatformCapabilities caps, Stream<DateTime> ticks) async =>
    WebBluetoothScanner(api: WebBluetoothApiImpl(), pollTicks: ticks);
