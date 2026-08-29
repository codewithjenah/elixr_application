import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/profile/widgets/completed_movements_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows current completed movements and hides retired movement names',
    (tester) async {
      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: const ScaffoldPage(
            content: CompletedMovementsSection(
              movementNames: [
                'Tap',
                'Clip',
                'Arm Stall',
                'Hand Stall',
                'Hand Stall',
              ],
            ),
          ),
        ),
      );

      expect(find.text('Hand Stall'), findsOneWidget);
      expect(find.text('Tap'), findsNothing);
      expect(find.text('Clip'), findsNothing);
      expect(find.text('Arm Stall'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('No completed movements yet.'), findsNothing);
    },
  );
}
