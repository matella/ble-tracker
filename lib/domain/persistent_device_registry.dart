import 'dart:async';
import 'dart:convert';

import 'interfaces.dart';
import 'key_value_store.dart';
import 'types.dart';

class PersistentDeviceRegistry implements DeviceRegistry {
  PersistentDeviceRegistry(this._store);

  static const storageKey = 'registry.devices.v1';

  final KeyValueStore _store;
  final _controller = StreamController<List<RegisteredDevice>>.broadcast();
  Map<String, RegisteredDevice>? _cache;

  Future<Map<String, RegisteredDevice>> _load() async {
    if (_cache != null) return _cache!;
    final raw = await _store.read(storageKey);
    final list = raw == null
        ? <RegisteredDevice>[]
        : (jsonDecode(raw) as List<Object?>)
            .map((e) =>
                RegisteredDevice.fromJson(e! as Map<String, Object?>))
            .toList();
    return _cache = {for (final d in list) d.id: d};
  }

  Future<void> _save(Map<String, RegisteredDevice> devices) async {
    _cache = devices;
    await _store.write(
        storageKey, jsonEncode(devices.values.map((d) => d.toJson()).toList()));
    _controller.add(devices.values.toList());
  }

  @override
  Stream<List<RegisteredDevice>> watchAll() {
    late StreamSubscription<List<RegisteredDevice>> subscription;
    late StreamController<List<RegisteredDevice>> output;

    output = StreamController<List<RegisteredDevice>>(
      onListen: () async {
        // Emit current state immediately when listener attaches
        output.add((await _load()).values.toList());
        // Subscribe to future changes
        subscription = _controller.stream.listen(
          output.add,
          onError: output.addError,
          onDone: output.close,
        );
      },
      onCancel: () async {
        await subscription.cancel();
      },
    );

    return output.stream;
  }

  @override
  Future<void> register(RegisteredDevice device) async {
    final devices = Map.of(await _load());
    devices[device.id] = device;
    await _save(devices);
  }

  Future<RegisteredDevice> _require(String deviceId) async {
    final device = (await _load())[deviceId];
    if (device == null) {
      throw ArgumentError.value(deviceId, 'deviceId', 'not registered');
    }
    return device;
  }

  @override
  Future<void> setTracking(String deviceId, bool enabled) async {
    final device = await _require(deviceId);
    final devices = Map.of(_cache!);
    devices[deviceId] = device.copyWith(trackingEnabled: enabled);
    await _save(devices);
  }

  @override
  Future<void> rename(String deviceId, String name) async {
    final device = await _require(deviceId);
    final devices = Map.of(_cache!);
    devices[deviceId] = device.copyWith(name: name);
    await _save(devices);
  }

  @override
  Future<void> remove(String deviceId) async {
    await _require(deviceId);
    final devices = Map.of(_cache!)..remove(deviceId);
    await _save(devices);
  }
}
