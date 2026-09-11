import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_dialog.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/class_challenge.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/class_challenge_repository.dart';
import 'package:elixr_application/features/class_challenges/class_challenges_pane.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClassChallengeRepository implements ClassChallengeRepository {
  _FakeClassChallengeRepository({this.challenges = const []});

  final List<ClassChallenge> challenges;
  ClassChallenge? createdChallenge;
  ClassChallenge? updatedChallenge;
  String? archivedChallengeId;

  @override
  Stream<List<ClassChallenge>> watchChallengesForGroup({
    required String groupId,
    required String teacherId,
  }) => Stream.value(challenges);

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchResultsForGroup({
    required String groupId,
    required String teacherId,
  }) => Stream.value(const []);

  @override
  Future<ClassChallenge> createChallenge({
    required ClassChallenge challenge,
  }) async {
    createdChallenge = challenge;
    return challenge;
  }

  @override
  Future<ClassChallenge> updateChallenge({
    required ClassChallenge challenge,
  }) async {
    updatedChallenge = challenge;
    return challenge;
  }

  @override
  Future<void> archiveChallenge({required String challengeId}) async {
    archivedChallengeId = challengeId;
  }

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
    expect(find.text('Create Challenge'), findsOneWidget);
    expect(find.text('Challenge details'), findsOneWidget);
    expect(find.text('Movement'), findsWidgets);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Challenge settings'), findsOneWidget);
    expect(
      find.text('Highest score wins. Scores range from 0 to 12.'),
      findsOneWidget,
    );
    expect(find.textContaining('Assessment V2'), findsNothing);
    expect(find.text('Attempts per trainee'), findsOneWidget);
    expect(find.text('Leave blank for unlimited attempts.'), findsOneWidget);
    expect(find.text('Goal score'), findsOneWidget);
    expect(
      find.text('Optional. Set a score trainees can aim for.'),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const Key('class_challenge_cancel_action')),
      ).height,
      tester.getSize(
        find.byKey(const Key('class_challenge_primary_action')),
      ).height,
    );

    final dialog = tester.widget<ElixDialog>(
      find.byKey(const Key('class_challenge_editor')),
    );
    expect(dialog.maxWidth, 760);
    expect(dialog.maxHeight, 780);

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
    final startHour = tester.widget<ComboBox<int>>(
      find.byKey(const Key('class_challenge_start_hour')),
    );
    expect(startHour.items!.map((item) => item.value), containsAll([1, 12]));
    expect(startHour.items!.map((item) => item.value), isNot(contains(0)));
    expect(startHour.items!.map((item) => item.value), isNot(contains(13)));
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

    final dialog = tester.widget<ElixDialog>(
      find.byKey(const Key('class_challenge_editor')),
    );
    expect(dialog.maxWidth, 576);
    expect(
      find.byKey(const Key('class_challenge_movement_preview')),
      findsOneWidget,
    );
    expect(find.text('Create Class Challenge'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create Challenge'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create dialog scrolls without overflow at a small window', (
    tester,
  ) async {
    await _pumpTeacherPane(tester, const Size(360, 500));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    expect(find.text('Create Class Challenge'), findsOneWidget);
    expect(find.byKey(const Key('class_challenge_movement_preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('12-hour challenge time conversion handles midnight and noon', () {
    final base = DateTime(2026, 9, 11, 9, 15);

    expect(classChallengeDisplayHour(DateTime(2026, 9, 11, 0)), 12);
    expect(classChallengeDisplayPeriod(DateTime(2026, 9, 11, 0)), 'AM');
    expect(
      classChallengeDateTimeFrom12Hour(base, hour: 12, minute: 0, period: 'AM'),
      DateTime(2026, 9, 11, 0),
    );

    expect(classChallengeDisplayHour(DateTime(2026, 9, 11, 12)), 12);
    expect(classChallengeDisplayPeriod(DateTime(2026, 9, 11, 12)), 'PM');
    expect(
      classChallengeDateTimeFrom12Hour(base, hour: 12, minute: 0, period: 'PM'),
      DateTime(2026, 9, 11, 12),
    );

    expect(
      classChallengeDateTimeFrom12Hour(base, hour: 1, minute: 30, period: 'PM'),
      DateTime(2026, 9, 11, 13, 30),
    );
  });

  testWidgets('creating stores the selected 12-hour time as UTC', (
    tester,
  ) async {
    final repository = _FakeClassChallengeRepository();
    await _pumpTeacherPane(
      tester,
      const Size(1440, 900),
      repository: repository,
    );
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    final startDate = tester
        .widget<DatePicker>(
          find.byKey(const Key('class_challenge_start_date')),
        )
        .selected!;
    final deadline = tester
        .widget<DatePicker>(
          find.byKey(const Key('class_challenge_deadline_date')),
        )
        .selected!;
    await tester.enterText(
      find.byKey(const Key('class_challenge_title')),
      'Evening challenge',
    );
    await tester.enterText(
      find.byKey(const Key('class_challenge_description')),
      'Complete the movement cleanly.',
    );

    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('class_challenge_start_hour')),
        )
        .onChanged!(5);
    await tester.pump();
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('class_challenge_start_minute')),
        )
        .onChanged!(30);
    await tester.pump();
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('class_challenge_start_period')),
        )
        .onChanged!('PM');
    await tester.pump();

    await tester.tap(find.text('Create Challenge'));
    await tester.pumpAndSettle();

    expect(repository.createdChallenge, isNotNull);
    expect(
      repository.createdChallenge!.startAt,
      DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        17,
        30,
      ).toUtc(),
    );
    expect(repository.createdChallenge!.deadline, deadline.toUtc());
  });

  testWidgets('empty title still blocks save', (tester) async {
    await _pumpTeacherPane(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Challenge'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a title of 80 characters or fewer.'),
      findsOneWidget,
    );
    expect(find.text('Create Class Challenge'), findsOneWidget);
  });

  testWidgets('editing displays local time and preserves stored UTC values', (
    tester,
  ) async {
    final existing = ClassChallenge(
      id: 'challenge-1',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      teacherDisplayName: 'Coach',
      title: 'Evening practice',
      description: 'Complete a clean toss.',
      movementName: movementCatalog.first.name,
      difficulty: movementCatalog.first.difficulty,
      prop: TrainingProp.bottle,
      startAt: DateTime.utc(2026, 9, 11, 17, 30),
      deadline: DateTime.utc(2026, 9, 18, 17, 30),
      attemptLimit: 3,
      targetScore: 8,
    );
    final repository = _FakeClassChallengeRepository(challenges: [existing]);
    await _pumpTeacherPane(
      tester,
      const Size(1440, 900),
      repository: repository,
    );

    await tester.tap(find.byKey(const Key('class_challenge_edit_challenge-1')));
    await tester.pumpAndSettle();

    final localStart = existing.startAt.toLocal();
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('class_challenge_start_hour')),
          )
          .value,
      classChallengeDisplayHour(localStart),
    );
    expect(
      tester
          .widget<ComboBox<String>>(
            find.byKey(const Key('class_challenge_start_period')),
          )
          .value,
      classChallengeDisplayPeriod(localStart),
    );

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repository.updatedChallenge, isNotNull);
    expect(repository.updatedChallenge!.startAt, existing.startAt);
    expect(repository.updatedChallenge!.deadline, existing.deadline);
    expect(repository.updatedChallenge!.attemptLimit, 3);
    expect(repository.updatedChallenge!.targetScore, 8);
  });

  testWidgets('archive confirmation explains that results are kept', (
    tester,
  ) async {
    final challenge = ClassChallenge(
      id: 'challenge-archive',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      teacherDisplayName: 'Coach',
      title: 'Archive me',
      description: 'Complete a clean toss.',
      movementName: movementCatalog.first.name,
      difficulty: movementCatalog.first.difficulty,
      prop: TrainingProp.bottle,
      startAt: DateTime.utc(2026, 9, 10, 9),
      deadline: DateTime.utc(2026, 9, 18, 17),
    );
    final repository = _FakeClassChallengeRepository(
      challenges: [challenge],
    );
    await _pumpTeacherPane(
      tester,
      const Size(1440, 900),
      repository: repository,
    );

    await tester.tap(
      find.byKey(const Key('class_challenge_archive_challenge-archive')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archive challenge?'), findsOneWidget);
    expect(
      find.textContaining('Existing attempts and leaderboard results will be kept.'),
      findsOneWidget,
    );
    expect(find.textContaining('Assessment V2'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(repository.archivedChallengeId, 'challenge-archive');
  });

  testWidgets('attempt and goal score validation keep their existing ranges', (
    tester,
  ) async {
    await _pumpTeacherPane(tester, const Size(1440, 900));
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('class_challenge_title')),
      'Practice challenge',
    );
    await tester.enterText(
      find.byKey(const Key('class_challenge_description')),
      'Complete the movement cleanly.',
    );
    await tester.enterText(
      find.byKey(const Key('class_challenge_attempts')),
      '21',
    );
    await tester.tap(find.text('Create Challenge'));
    await tester.pumpAndSettle();

    expect(
      find.text('Attempt limit must be between 1 and 20.'),
      findsOneWidget,
    );
    expect(find.text('Create Class Challenge'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('class_challenge_attempts')),
      '',
    );
    await tester.enterText(
      find.byKey(const Key('class_challenge_target')),
      '13',
    );
    await tester.tap(find.text('Create Challenge'));
    await tester.pumpAndSettle();

    expect(find.text('Target score must be between 0 and 12.'), findsOneWidget);
  });
}

Future<void> _pumpTeacherPane(
  WidgetTester tester,
  Size size, {
  _FakeClassChallengeRepository? repository,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(
        content: ClassChallengesPane(
          repository: repository ?? _FakeClassChallengeRepository(),
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
