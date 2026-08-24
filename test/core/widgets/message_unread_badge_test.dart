import 'package:elixr_application/core/widgets/message_unread_badge.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides zero and caps the visible count at 99+', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: Row(
          children: [
            MessageUnreadBadge(count: 0),
            MessageUnreadBadge(count: 125),
          ],
        ),
      ),
    );

    expect(find.text('0'), findsNothing);
    expect(find.text('99+'), findsOneWidget);
  });
}
