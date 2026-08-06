import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';

/// NFR-6: adapter-off / permission-revoked surface as a recoverable banner.
class ScannerStatusBanner extends ConsumerWidget {
  const ScannerStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(scannerStatusProvider).value;
    final (text, color) = switch (status) {
      ScannerStatus.unavailable => (
          'Bluetooth is off — turn it on to resume tracking.',
          Colors.orange
        ),
      ScannerStatus.unauthorized => (
          'Bluetooth permission needed — grant permission to scan.',
          Colors.red
        ),
      _ => (null, Colors.transparent),
    };
    if (text == null) return const SizedBox.shrink();
    return Material(
      key: const Key('status-banner'),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
