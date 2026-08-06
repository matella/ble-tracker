import 'dart:async';

import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart';

import 'web_bluetooth_api.dart';

/// Real implementation over package:flutter_web_bluetooth. Verified against
/// the 1.1.0 sources in ~/.pub-cache (pub.dev) at implementation time.
///
/// Web Bluetooth exposes RSSI via `watchAdvertisements()` events, not a
/// direct read — [readRssi] returns the latest advertisement RSSI seen for
/// a device, cached from the advertisement event stream. Advertisement
/// watching requires Chromium >= 111 with no flag.
///
/// package:flutter_web_bluetooth itself already conditionally exports a
/// non-web "unsupported" implementation (`if (dart.library.js_interop)`) so
/// this file compiles cleanly on VM targets too — `isSupported` simply
/// reports false there, and `requestDevice` would throw if ever called
/// (which it isn't, off the web).
class WebBluetoothApiImpl implements WebBluetoothApi {
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, double> _latestRssi = {};

  @override
  bool get isSupported => FlutterWebBluetooth.instance.isBluetoothApiSupported;

  @override
  List<String> get pairedDeviceIds => _devices.keys.toList();

  @override
  Future<String> requestDevice() async {
    final device = await FlutterWebBluetooth.instance.requestDevice(
      RequestOptionsBuilder.acceptAllDevices(),
    );
    _devices[device.id] = device;
    device.advertisements.listen((event) {
      final rssi = event.rssi;
      if (rssi != null) _latestRssi[device.id] = rssi.toDouble();
    });
    await device.watchAdvertisements();
    return device.id;
  }

  @override
  Future<double?> readRssi(String deviceId) async => _latestRssi[deviceId];

  @override
  Future<String?> deviceName(String deviceId) async =>
      _devices[deviceId]?.name;
}
