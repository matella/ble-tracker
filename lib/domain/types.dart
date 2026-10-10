enum ProximityBand { immediate, near, mid, far }

enum DeviceVisibility { visible, notVisible, trackingOff }

enum ScannerStatus { idle, scanning, unavailable, unauthorized }

enum ScanProfile { lowLatency, balanced }

enum CapabilityTier { tierA, tierB, tierC }

enum DeviceType { headphones, phone, tag, watch, other }

class ScanObservation {
  const ScanObservation({
    required this.deviceId,
    required this.rssi,
    required this.timestamp,
    this.txPower,
    this.advertisedName,
  });

  final String deviceId;
  final double rssi;
  final double? txPower;
  final DateTime timestamp;
  final String? advertisedName;

  @override
  bool operator ==(Object other) =>
      other is ScanObservation &&
      other.deviceId == deviceId &&
      other.rssi == rssi &&
      other.txPower == txPower &&
      other.timestamp == timestamp &&
      other.advertisedName == advertisedName;

  @override
  int get hashCode =>
      Object.hash(deviceId, rssi, txPower, timestamp, advertisedName);
}

class DistanceEstimate {
  const DistanceEstimate({required this.meters, required this.band});

  final double meters;
  final ProximityBand band;

  @override
  bool operator ==(Object other) =>
      other is DistanceEstimate && other.meters == meters && other.band == band;

  @override
  int get hashCode => Object.hash(meters, band);
}

class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.name,
    required this.type,
    this.trackingEnabled = true,
    this.calibratedRssiAt1m,
  });

  /// Stored records written before calibration existed have no
  /// `calibratedRssiAt1m` key; they load as uncalibrated (null).
  factory RegisteredDevice.fromJson(Map<String, Object?> json) =>
      RegisteredDevice(
        id: json['id']! as String,
        name: json['name']! as String,
        type: DeviceType.values.byName(json['type']! as String),
        trackingEnabled: json['trackingEnabled']! as bool,
        calibratedRssiAt1m: (json['calibratedRssiAt1m'] as num?)?.toDouble(),
      );

  final String id;
  final String name;
  final DeviceType type;
  final bool trackingEnabled;

  /// Reference RSSI measured at 1 m (OQ-3). When set, it replaces the
  /// advertised or default TxPower for this device. Null when uncalibrated.
  final double? calibratedRssiAt1m;

  RegisteredDevice copyWith({String? name, bool? trackingEnabled}) =>
      RegisteredDevice(
        id: id,
        name: name ?? this.name,
        type: type,
        trackingEnabled: trackingEnabled ?? this.trackingEnabled,
        calibratedRssiAt1m: calibratedRssiAt1m,
      );

  /// Sets or clears the calibration. Separate from [copyWith] because a
  /// nullable `copyWith` argument cannot distinguish "clear" from "keep".
  RegisteredDevice withCalibration(double? rssiAt1m) => RegisteredDevice(
    id: id,
    name: name,
    type: type,
    trackingEnabled: trackingEnabled,
    calibratedRssiAt1m: rssiAt1m,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'trackingEnabled': trackingEnabled,
    'calibratedRssiAt1m': calibratedRssiAt1m,
  };

  @override
  bool operator ==(Object other) =>
      other is RegisteredDevice &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.trackingEnabled == trackingEnabled &&
      other.calibratedRssiAt1m == calibratedRssiAt1m;

  @override
  int get hashCode =>
      Object.hash(id, name, type, trackingEnabled, calibratedRssiAt1m);
}

class TrackedDeviceState {
  const TrackedDeviceState({
    required this.device,
    required this.visibility,
    this.estimate,
    this.lastSeen,
  });

  final RegisteredDevice device;
  final DeviceVisibility visibility;
  final DistanceEstimate? estimate;
  final DateTime? lastSeen;

  @override
  bool operator ==(Object other) =>
      other is TrackedDeviceState &&
      other.device == device &&
      other.visibility == visibility &&
      other.estimate == estimate &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(device, visibility, estimate, lastSeen);
}
