import 'package:async/async.dart';
import 'package:bluez/bluez.dart';

import '../../domain/types.dart';
import 'bluez_api.dart';

/// Real BlueZ D-Bus calls via package:bluez. Verify API names against
/// current package docs (pub.dev) at implementation time. Symbol names
/// checked against bluez 0.8.3 from pub.dev.
class BlueZApiImpl implements BlueZApi {
  BlueZApiImpl(this._client);

  final BlueZClient _client;

  BlueZAdapter get _adapter => _client.adapters.first;

  @override
  Stream<bool> adapterOn() => _adapter.propertiesChanged
      .where((props) => props.contains('Powered'))
      .map((_) => _adapter.powered);

  @override
  Stream<ScanObservation> scanResults() {
    final group = StreamGroup<ScanObservation>();

    void watchRssi(BlueZDevice device) => group.add(device.propertiesChanged
        .where((props) => props.contains('RSSI'))
        .map((_) => _toObservation(device)));

    _client.devices.forEach(watchRssi);
    group.add(_client.deviceAdded.map((device) {
      // deviceAdded is a broadcast stream: registering the per-device RSSI
      // stream as a side effect here runs immediately per event, unlike
      // asyncExpand which would serialize on the never-ending inner streams.
      watchRssi(device);
      return _toObservation(device);
    }));
    return group.stream;
  }

  ScanObservation _toObservation(BlueZDevice d) => ScanObservation(
        deviceId: d.address,
        rssi: d.rssi.toDouble(),
        txPower: d.txPower == 0 ? null : d.txPower.toDouble(),
        timestamp: DateTime.now(),
        advertisedName: d.name.isEmpty ? null : d.name,
      );

  @override
  Future<void> startDiscovery() => _adapter.startDiscovery();

  @override
  Future<void> stopDiscovery() => _adapter.stopDiscovery();
}
