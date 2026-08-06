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
  Stream<ScanObservation> scanResults() async* {
    await for (final device in _client.deviceAdded) {
      yield _toObservation(device);
    }
    // Note: also merge per-device RSSI propertiesChanged for already-known
    // devices — StreamGroup.merge from package:async:
    //   StreamGroup.merge([_client.deviceAdded.map(...), ...rssiStreams])
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
