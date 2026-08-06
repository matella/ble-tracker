import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/types.dart';
import 'fbp_api.dart';

/// Real flutter_blue_plus calls. Verified against flutter_blue_plus 2.3.11
/// (the version resolved by pubspec.lock) — see task-12-report.md for the
/// API surface check. Re-verify these names if the plugin major bumps.
class FbpApiImpl implements FbpApi {
  @override
  Stream<bool> adapterOn() => FlutterBluePlus.adapterState
      .map((s) => s == BluetoothAdapterState.on);

  @override
  Stream<ScanObservation> scanResults() =>
      FlutterBluePlus.onScanResults.expand((results) => results.map(
            (r) => ScanObservation(
              deviceId: r.device.remoteId.str,
              rssi: r.rssi.toDouble(),
              txPower: r.advertisementData.txPowerLevel?.toDouble(),
              timestamp: DateTime.now(),
              advertisedName: r.advertisementData.advName.isEmpty
                  ? null
                  : r.advertisementData.advName,
            ),
          ));

  /// Maps a missing/revoked BLE permission (NFR-6) to [FbpPermissionDenied].
  /// flutter_blue_plus 2.3.11 doesn't have a dedicated permission error
  /// code — it surfaces either a [FlutterBluePlusException] (with a
  /// platform-specific `description`) or, on some Android paths, a raw
  /// [PlatformException] straight from the plugin channel. Match
  /// conservatively on "permission" appearing in whatever text either
  /// exception carries; anything else is rethrown unchanged.
  @override
  Future<void> startScan({required bool lowLatency}) async {
    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode:
            lowLatency ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
      );
    } on FlutterBluePlusException catch (e) {
      if (_mentionsPermission(e.description)) throw FbpPermissionDenied();
      rethrow;
    } on PlatformException catch (e) {
      if (_mentionsPermission(e.code) || _mentionsPermission(e.message)) {
        throw FbpPermissionDenied();
      }
      rethrow;
    }
  }

  bool _mentionsPermission(String? text) =>
      text?.toLowerCase().contains('permission') ?? false;

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();
}
