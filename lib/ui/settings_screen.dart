import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/settings.dart';
import '../state/providers.dart';

/// FR-9: user-tunable path-loss environment factor `n`.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Value held while the thumb is dragged. The composer is rebuilt on every
  // committed change, so only the release is applied, not each drag frame.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(environmentFactorProvider);
    final shown = _dragging ?? stored;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Environment factor (n)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'The path-loss exponent that turns signal strength into distance: '
            'about 2.0 in open air, 2.7–3.0 indoors, up to 4.0 behind heavy '
            'obstructions. Changing it restarts distance smoothing, so devices '
            'show as not visible until each is heard again.',
          ),
          Slider(
            key: const Key('environment-factor-slider'),
            min: environmentFactorMin,
            max: environmentFactorMax,
            divisions: 20,
            label: shown.toStringAsFixed(1),
            value: shown,
            onChanged: (v) => setState(() => _dragging = _round(v)),
            onChangeEnd: _commit,
          ),
          Center(child: Text('n = ${shown.toStringAsFixed(1)}')),
        ],
      ),
    );
  }

  void _commit(double value) {
    setState(() => _dragging = null);
    ref.read(environmentFactorProvider.notifier).set(_round(value));
  }

  // The slider steps in 0.1; round away binary noise such as 2.7000000001.
  static double _round(double v) => double.parse(v.toStringAsFixed(1));
}
