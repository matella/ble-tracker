/// Tier C manual-discovery entry point (FR-3). Implemented by scanners that
/// can invoke a platform device chooser from a user gesture (currently only
/// [WebBluetoothScanner]). Surfaced separately from [BleScanner] so the UI
/// layer can check for it without every scanner needing a no-op stub.
abstract interface class ManualPairing {
  Future<void> pairNewDevice();
}
