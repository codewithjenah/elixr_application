import 'package:elixr_teacher/features/student_progress/student_progress_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatPracticeDuration preserves its public boundary contract', () {
    expect(formatPracticeDuration(0), '0 min');
    expect(formatPracticeDuration(-1), '0 min');
    expect(formatPracticeDuration(30), '< 1 min');
    expect(formatPracticeDuration(59), '< 1 min');
    expect(formatPracticeDuration(60), '1 min');
    expect(formatPracticeDuration(3599), '59 min');
    expect(formatPracticeDuration(3600), '1 hr');
    expect(formatPracticeDuration(3725), '1 hr 2 min');
    expect(formatPracticeDuration(10860), '3 hr 1 min');
  });

  testWidgets('formatSessionDate rejects absent and malformed timestamps', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(formatSessionDate(context, null), 'Date unavailable');
    expect(formatSessionDate(context, 'not-a-date'), 'Date unavailable');
    expect(
      formatSessionDate(context, '2026-08-14T00:00:00Z'),
      formatSessionDate(context, '2026-08-14T08:00:00+08:00'),
    );
  });
}
