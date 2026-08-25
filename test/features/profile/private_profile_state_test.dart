import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/profile/widgets/private_profile_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpState(WidgetTester tester, {required bool ownerIsTeacher}) {
    return tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: PrivateProfileState(ownerIsTeacher: ownerIsTeacher),
        ),
      ),
    );
  }

  testWidgets('trainee locked copy mentions player and leaderboard identity', (
    tester,
  ) async {
    await pumpState(tester, ownerIsTeacher: false);

    expect(find.text('This profile is locked'), findsOneWidget);
    expect(
      find.text(
        'This player has locked their detailed activity. '
        'Basic leaderboard identity remains visible.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('This teacher has locked'), findsNothing);
  });

  testWidgets(
    'teacher locked copy does not use trainee player/leaderboard wording',
    (tester) async {
      await pumpState(tester, ownerIsTeacher: true);

      expect(find.text('This profile is locked'), findsOneWidget);
      expect(
        find.text(
          'This teacher has locked their detailed activity. '
          'Name and avatar remain visible.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('This player has locked'), findsNothing);
      expect(find.textContaining('leaderboard identity'), findsNothing);
    },
  );
}
