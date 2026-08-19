import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/learning/learning_center_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('learning center renders at desktop and compact widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in const [Size(1440, 900), Size(560, 900)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        FluentApp(theme: AppTheme.dark, home: const LearningCenterScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Help & Tutorials'), findsOneWidget);
      expect(find.text('Start with the essentials'), findsOneWidget);
      expect(find.text('How your performance is measured'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
