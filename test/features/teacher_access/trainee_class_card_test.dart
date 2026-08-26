import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/teacher_access/trainee_class_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('class accents stay inside the ELIXR pink-purple palette', () {
    const ids = [
      'group-1',
      'group-2',
      'a',
      'b',
      'c',
      'd',
      'BSIT-4A',
      'BSHM-4A',
      'long-classroom-identifier',
    ];
    const brandColors = [
      AppColors.primary,
      AppColors.primarySoft,
      AppColors.accent,
      AppColors.accentSoft,
    ];
    for (final id in ids) {
      final accent = traineeClassAccent(id);
      expect(brandColors, contains(accent.start), reason: id);
      expect(brandColors, contains(accent.end), reason: id);
    }
  });

  testWidgets('class card keeps the group key and opens on tap', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.light,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-1',
                className: 'BSIT-4A',
                teacherDisplayName: 'Jiro Lapuz',
                onOpen: () => opened = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('teacher_access_group_group-1')),
      findsOneWidget,
    );
    expect(find.text('BSIT-4A'), findsOneWidget);
    expect(find.text('Jiro Lapuz'), findsOneWidget);
    expect(find.text('Open classwork'), findsOneWidget);

    await tester.tap(find.byKey(const Key('teacher_access_group_group-1')));
    expect(opened, isTrue);
  });
}
