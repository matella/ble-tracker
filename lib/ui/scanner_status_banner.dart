import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../state/providers.dart';

/// NFR-6: adapter-off / permission-revoked surface as a recoverable banner.
/// Colours come from the theme so the banner stays legible in light and
/// dark modes.
class ScannerStatusBanner extends ConsumerWidget {
  const ScannerStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(scannerStatusProvider).value;
    final resuming = ref.watch(resumeNoticeProvider);
    final scheme = Theme.of(context).colorScheme;
    final (text, background, foreground) = switch (status) {
      ScannerStatus.unavailable => (
          'Bluetooth is off — turn it on to resume tracking.',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      ScannerStatus.unauthorized => (
          'Bluetooth permission needed — grant permission to scan.',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      // Lower priority than a broken scanner: only shown while scanning works.
      _ when resuming => (
          'Updates were paused in the background — resuming.',
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      _ => (null, Colors.transparent, Colors.transparent),
    };
    if (text == null) return const SizedBox.shrink();
    return Material(
      key: const Key('status-banner'),
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: TextStyle(color: foreground)),
      ),
    );
  }
}
