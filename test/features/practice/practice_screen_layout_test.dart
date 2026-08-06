import 'package:elixr_application/core/constants/app_spacing.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/practice/practice_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aspectTolerance = 0.02;

  group('PracticeScreen layout metrics', () {
    test('desktop camera size preserves 4:3 within workspace bounds', () {
      const contentWidth = 1400.0;
      const workspaceHeight = 720.0;

      final size = PracticeScreen.desktopCameraSize(
        contentWidth: contentWidth,
        workspaceHeight: workspaceHeight,
      );

      expect(size.width / size.height, closeTo(640 / 480, aspectTolerance));
      expect(size.height, lessThanOrEqualTo(workspaceHeight));
      expect(
        size.width,
        lessThanOrEqualTo(
          contentWidth -
              AppSpacing.practicePanelMinWidth -
              AppSpacing.practiceCameraPanelGap,
        ),
      );
    });

    test('stacked camera size preserves 4:3 from content width', () {
      const contentWidth = 820.0;

      final size = PracticeScreen.stackedCameraSize(contentWidth);

      expect(size.width, contentWidth);
      expect(size.width / size.height, closeTo(640 / 480, aspectTolerance));
    });

    test('desktop camera size fits height-limited workspace', () {
      const contentWidth = 1200.0;
      const workspaceHeight = 360.0;

      final size = PracticeScreen.desktopCameraSize(
        contentWidth: contentWidth,
        workspaceHeight: workspaceHeight,
      );

      expect(size.height, closeTo(workspaceHeight, 0.5));
      expect(size.width / size.height, closeTo(640 / 480, aspectTolerance));
    });
  });

  group('Practice page background shell', () {
    testWidgets('fills scaffold content without default page padding', (
      tester,
    ) async {
      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              return ScaffoldPage(
                padding: EdgeInsets.zero,
                content: SizedBox.expand(
                  child: DecoratedBox(
                    decoration: AppTheme.practicePageBackground(context),
                    child: const Center(child: Text('practice-body')),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final scaffoldFinder = find.byType(ScaffoldPage);
      final scaffoldBox = tester.renderObject<RenderBox>(scaffoldFinder);
      final decoratedFinder = find.byType(DecoratedBox).first;
      final decoratedBox = tester.renderObject<RenderBox>(decoratedFinder);

      expect(decoratedBox.size, scaffoldBox.size);
      expect(find.text('practice-body'), findsOneWidget);
    });
  });
}
