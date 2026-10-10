import 'package:ble_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resume notice starts off, shows, and clears', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(resumeNoticeProvider), isFalse);

    c.read(resumeNoticeProvider.notifier).show();
    expect(c.read(resumeNoticeProvider), isTrue);

    c.read(resumeNoticeProvider.notifier).clear();
    expect(c.read(resumeNoticeProvider), isFalse);
  });
}
