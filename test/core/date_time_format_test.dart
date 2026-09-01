import 'package:elixr_application/core/utils/date_time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a readable month name and 12-hour time', () {
    final value = DateTime(2026, 8, 21, 13);

    expect(formatElixrDateTime(value), 'Aug 21, 2026 1:00 PM');
    expect(formatElixrDate(value), 'Aug 21, 2026');
    expect(formatElixrTime(value), '1:00 PM');
  });
}
