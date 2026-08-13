import 'package:flutter_test/flutter_test.dart';

import 'package:elixr_teacher/main.dart';

void main() {
  testWidgets('shows Elixr Teacher placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ElixrTeacherApp());

    expect(find.text('Elixr Teacher'), findsOneWidget);
  });
}
