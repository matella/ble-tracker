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
  int get hashCode => Object.hash(deviceId, rssi, txPower, timestamp, advertisedName);
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
  });

  factory RegisteredDevice.fromJson(Map<String, Object?> json) =>
      RegisteredDevice(
        id: json['id']! as String,
        name: json['name']! as String,
        type: DeviceType.values.byName(json['type']! as String),
        trackingEnabled: json['trackingEnabled']! as bool,
      );

  final String id;
  final String name;
  final DeviceType type;
  final bool trackingEnabled;

  RegisteredDevice copyWith({String? name, bool? trackingEnabled}) =>
      RegisteredDevice(
        id: id,
        name: name ?? this.name,
        type: type,
        trackingEnabled: trackingEnabled ?? this.trackingEnabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'trackingEnabled': trackingEnabled,
      };

  @override
  bool operator ==(Object other) =>
      other is RegisteredDevice &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.trackingEnabled == trackingEnabled;

  @override
  int get hashCode => Object.hash(id, name, type, trackingEnabled);
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
