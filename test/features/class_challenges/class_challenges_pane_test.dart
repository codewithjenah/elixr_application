import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/class_challenge.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/class_challenge_repository.dart';
import 'package:elixr_application/features/class_challenges/class_challenges_pane.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClassChallengeRepository implements ClassChallengeRepository {
  @override
  Stream<List<ClassChallenge>> watchChallengesForGroup({
    required String groupId,
    required String teacherId,
  }) => Stream.value(const []);

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchResultsForGroup({
    required String groupId,
    required String teacherId,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Teacher challenge subscription requires the active Teacher identity',
    () {
      expect(
        canStartTeacherChallengeSubscription(
          currentUserId: 'teacher-1',
          teacherId: 'teacher-1',
        ),
        isTrue,
      );
      expect(
        canStartTeacherChallengeSubscription(
          currentUserId: 'teacher-2',
          teacherId: 'teacher-1',
        ),
        isFalse,
      );
      expect(
        canStartTeacherChallengeSubscription(
          currentUserId: '',
          teacherId: 'teacher-1',
        ),
        isFalse,
      );
    },
  );

  test('challenge editor constraints target a wide desktop dialog', () {
    final desktop = classChallengeEditorConstraints(const Size(1440, 900));
    expect(desktop.maxWidth, 760);
    expect(desktop.minWidth, 760);
    expect(desktop.maxHeight, 780);

    final compact = classChallengeEditorConstraints(const Size(640, 720));
    expect(compact.maxWidth, 576);
    expect(compact.minWidth, 576);
    expect(compact.maxHeight, 656);

    final narrow = classChallengeEditorConstraints(const Size(360, 500));
    expect(narrow.maxWidth, 320);
    expect(narrow.minWidth, 320);
    expect(narrow.maxHeight, 436);
  });

  testWidgets('create dialog is wide and shows movement artwork', (
    tester,
  ) async {
    await _pumpTeacherPane(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    expect(find.text('Create Class Challenge'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('CHALLENGE DETAILS'), findsOneWidget);
    expect(find.text('MOVEMENT + PROP'), findsOneWidget);
    expect(find.text('START + DEADLINE'), findsOneWidget);
    expect(find.text('ATTEMPT LIMIT + TARGET SCORE'), findsOneWidget);
    expect(
      find.text('Best Assessment V2 rubric total wins (maximum 12).'),
      findsOneWidget,
    );

    final dialog = tester.widget<ContentDialog>(
      find.byKey(const Key('class_challenge_editor')),
    );
    expect(dialog.constraints.maxWidth, 760);
    expect(dialog.constraints.minWidth, 760);

    final preview = tester.widget<MovementImage>(
      find.byKey(const Key('class_challenge_movement_preview')),
    );
    expect(preview.movementName, movementCatalog.first.name);
    expect(preview.prop, TrainingProp.bottle);

    final combo = tester.widget<ComboBox<Movement>>(
      find.byKey(const Key('class_challenge_movement')),
    );
    expect(
      combo.items!.length,
      movementCatalog.where((item) => item.enabled).length,
    );
    expect(combo.items!.first.child, isA<ClassChallengeMovementOption>());
    final option = combo.items!.first.child as ClassChallengeMovementOption;
    expect(option.movement.name, movementCatalog.first.name);
    expect(option.prop, TrainingProp.bottle);
    expect(find.byType(ClassChallengeMovementOption), findsWidgets);
    expect(find.byType(DatePicker), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('prop changes update bottle and shaker artwork', (tester) async {
    await _pumpTeacherPane(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    final handStall = movementCatalog.firstWhere(
      (item) => item.name == 'Hand Stall',
    );
    tester
        .widget<ComboBox<Movement>>(
          find.byKey(const Key('class_challenge_movement')),
        )
        .onChanged!(handStall);
    await tester.pump();

    var preview = tester.widget<MovementImage>(
      find.byKey(const Key('class_challenge_movement_preview')),
    );
    expect(preview.movementName, 'Hand Stall');
    expect(preview.prop, TrainingProp.bottle);

    tester
        .widget<ComboBox<TrainingProp>>(
          find.byKey(const Key('class_challenge_prop')),
        )
        .onChanged!(TrainingProp.shaker);
    await tester.pump();

    preview = tester.widget<MovementImage>(
      find.byKey(const Key('class_challenge_movement_preview')),
    );
    expect(preview.prop, TrainingProp.shaker);

    final combo = tester.widget<ComboBox<Movement>>(
      find.byKey(const Key('class_challenge_movement')),
    );
    final option = combo.items!
        .map((item) => item.child)
        .whereType<ClassChallengeMovementOption>()
        .firstWhere((item) => item.movement.name == 'Hand Stall');
    expect(option.prop, TrainingProp.shaker);
  });

  testWidgets('create dialog stays usable on a narrow window', (tester) async {
    await _pumpTeacherPane(tester, const Size(640, 720));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    final dialog = tester.widget<ContentDialog>(
      find.byKey(const Key('class_challenge_editor')),
    );
    expect(dialog.constraints.maxWidth, 576);
    expect(
      find.byKey(const Key('class_challenge_movement_preview')),
      findsOneWidget,
    );
    expect(find.text('Create Class Challenge'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty title still blocks save', (tester) async {
    await _pumpTeacherPane(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a title of 80 characters or fewer.'),
      findsOneWidget,
    );
    expect(find.text('Create Class Challenge'), findsOneWidget);
  });
}

Future<void> _pumpTeacherPane(WidgetTester tester, Size size) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(
        content: ClassChallengesPane(
          repository: _FakeClassChallengeRepository(),
          groupId: 'group-1',
          teacherId: 'teacher-1',
          teacherDisplayName: 'Coach',
          currentUserId: 'teacher-1',
          isTeacher: true,
          groupIsActive: true,
          participantCount: 0,
          onOpenLeaderboard: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
