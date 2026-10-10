import 'package:ble_tracker/ui/device_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('last seen is "never" when the device has not been observed', () {
    expect(formatLastSeen(null), 'never');
  });

  test('last seen is an absolute local yyyy-MM-dd HH:mm:ss', () {
    final utc = DateTime.utc(2026, 3, 9, 7, 4, 5);
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(
      formatLastSeen(utc),
      '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}',
    );
  });
}
