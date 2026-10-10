import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/rssi_calibration.dart';
import '../domain/types.dart';
import '../state/providers.dart';

/// FR-17: name, raw RSSI, smoothed distance, band, last-seen. Also the entry
/// point for calibrating the device at 1 m (OQ-3).
class DeviceDetailSheet extends ConsumerStatefulWidget {
  const DeviceDetailSheet({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends ConsumerState<DeviceDetailSheet> {
  RssiCalibrationSession? _session;
  double? _measured;
  bool _implausible = false;
  ProviderSubscription<AsyncValue<ScanObservation>>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _startCalibration() {
    _subscription?.close();
    final session = RssiCalibrationSession();
    setState(() {
      _session = session;
      _measured = null;
      _implausible = false;
    });
    // Readings are the device's own observations; timestamps come from the
    // scanner, so the window is measured in scan time, not wall-clock time.
    _subscription = ref.listenManual(discoveryObservationsProvider, (_, next) {
      final obs = next.value;
      if (obs == null || obs.deviceId != widget.deviceId) return;
      session.add(obs.rssi, obs.timestamp);
      final result = session.result;
      if (result == null) {
        // Still measuring: refresh the reading count.
        setState(() {});
        return;
      }
      _subscription?.close();
      _subscription = null;
      setState(() {
        _measured = result;
        _session = null;
      });
    });
  }

  Future<void> _saveCalibration(double value) async {
    if (!RssiCalibrationSession.isPlausibleReference(value)) {
      setState(() {
        _implausible = true;
        _measured = null;
      });
      return;
    }
    await ref
        .read(deviceRegistryProvider)
        .setCalibration(widget.deviceId, value);
    setState(() => _measured = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceStatesProvider).value?[widget.deviceId];
    final rssi = ref.watch(latestRssiProvider).value?[widget.deviceId];
    if (state == null) return const SizedBox.shrink();
    final e = state.estimate;
    final visible = state.visibility == DeviceVisibility.visible;
    final calibrated = state.device.calibratedRssiAt1m;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.device.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text('Raw RSSI: ${rssi?.toStringAsFixed(0) ?? '—'} dBm'),
          Text(
            e == null
                ? 'Distance: —'
                : 'Distance: ${e.meters.toStringAsFixed(1)} m (${e.band.name})',
          ),
          Text('Last seen: ${formatLastSeen(state.lastSeen)}'),
          const Divider(height: 32),
          Text(
            calibrated == null
                ? 'Calibration: none (uses advertised TxPower)'
                : 'Calibrated: ${calibrated.toStringAsFixed(0)} dBm at 1 m',
          ),
          const SizedBox(height: 8),
          if (_session != null)
            Text(
              'Measuring… stand 1 m away (${_session!.sampleCount} readings)',
            )
          else if (_measured != null)
            Text('Measured ${_measured!.toStringAsFixed(0)} dBm at 1 m')
          else if (_implausible)
            const Text(
              'That reading looks wrong — stand 1 m away and try again.',
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (_measured != null)
                FilledButton(
                  key: const Key('save-calibration'),
                  onPressed: () => _saveCalibration(_measured!),
                  child: const Text('Save'),
                )
              else
                FilledButton.tonal(
                  key: const Key('calibrate-button'),
                  onPressed: visible && _session == null
                      ? _startCalibration
                      : null,
                  child: const Text('Calibrate at 1 m'),
                ),
              if (calibrated != null)
                OutlinedButton(
                  key: const Key('reset-calibration'),
                  onPressed: () => ref
                      .read(deviceRegistryProvider)
                      .setCalibration(widget.deviceId, null),
                  child: const Text('Reset'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Local time as `yyyy-MM-dd HH:mm:ss`, or `never`. Absolute on purpose: a
/// relative "5 s ago" would need a current time, and time is injected here.
@visibleForTesting
String formatLastSeen(DateTime? time) {
  if (time == null) return 'never';
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
