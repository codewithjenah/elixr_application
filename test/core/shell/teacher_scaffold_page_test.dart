import 'package:elixr_application/core/shell/teacher_shell.dart';
import 'package:elixr_application/core/constants/app_spacing.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildPage(FluentThemeData theme) {
    return FluentApp(
      theme: theme,
      home: const TeacherScaffoldPage(
        header: PageHeader(title: Text('Dashboard')),
        content: Text('Ambient content'),
      ),
    );
  }

  testWidgets('keeps Fluent scaffold transparent over the ambient background', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(AppTheme.dark));

    final scaffoldContext = tester.element(find.byType(ScaffoldPage));
    expect(
      FluentTheme.of(scaffoldContext).scaffoldBackgroundColor,
      Colors.transparent,
    );
    expect(
      tester.getTopLeft(find.byType(PageHeader)).dy,
      AppSpacing.pageTopInset,
    );
    expect(find.text('Ambient content'), findsOneWidget);
  });
}
