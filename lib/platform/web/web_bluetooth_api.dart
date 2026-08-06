/// Everything WebBluetoothScanner needs from the browser's Web Bluetooth
/// API, as plain Dart so tests can fake it.
abstract interface class WebBluetoothApi {
  /// Whether `navigator.bluetooth` is present in this browser (false on
  /// Safari and non-web platforms).
  bool get isSupported;

  /// Invokes the browser's device chooser (must be called from a user
  /// gesture). Returns the id of the paired device.
  Future<String> requestDevice();

  /// Latest known RSSI for a previously-paired device, or null if none has
  /// been observed yet.
  Future<double?> readRssi(String deviceId);

  /// Latest known advertised name for a previously-paired device.
  Future<String?> deviceName(String deviceId);

  /// Ids of all devices paired so far this session.
  List<String> get pairedDeviceIds;
}
