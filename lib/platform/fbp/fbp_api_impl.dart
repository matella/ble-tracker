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

  @override
  Future<void> startScan({required bool lowLatency}) => FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode:
            lowLatency ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
      );

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();
}
