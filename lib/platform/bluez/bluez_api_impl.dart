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
    // Merges (a) an observation for every newly-added device plus its
    // subsequent RSSI-bearing property changes, with (b) RSSI property
    // changes for devices already known when this is called — otherwise
    // devices seen before scanResults() was subscribed would only ever
    // yield their first observation.
    final group = StreamGroup<ScanObservation>();
    group.add(_client.deviceAdded.asyncExpand((device) async* {
      yield _toObservation(device);
      yield* device.propertiesChanged
          .where((props) => props.contains('RSSI'))
          .map((_) => _toObservation(device));
    }));
    for (final device in _client.devices) {
      group.add(device.propertiesChanged
          .where((props) => props.contains('RSSI'))
          .map((_) => _toObservation(device)));
    }
    // No close(): deviceAdded never completes on its own, so the merged
    // stream would never finish regardless — nothing is gained by closing
    // the group to further additions.
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
