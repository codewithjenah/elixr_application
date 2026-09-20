import 'dart:async';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_dialog.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/class_challenge.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/class_challenge_repository.dart';
import 'package:elixr_application/features/class_challenges/class_challenges_pane.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

class _FakeClassChallengeRepository implements ClassChallengeRepository {
  _FakeClassChallengeRepository({this.challenges = const []});

  final List<ClassChallenge> challenges;
  ClassChallenge? createdChallenge;
  ClassChallenge? updatedChallenge;
  String? archivedChallengeId;
  int permanentDeleteCalls = 0;
  String? permanentlyDeletedChallengeId;
  Completer<void>? permanentDeleteGate;
  Object? permanentDeleteError;

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
  Future<void> permanentlyDeleteChallenge({
    required String challengeId,
    required String confirmation,
  }) async {
    permanentDeleteCalls++;
    final gate = permanentDeleteGate;
    if (gate != null) await gate.future;
    final error = permanentDeleteError;
    if (error != null) throw error;
    permanentlyDeletedChallengeId = challengeId;
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

  testWidgets('challenge card shows artwork for its movement and prop', (
    tester,
  ) async {
    final movement = movementCatalog.firstWhere(
      (item) => item.name == 'Forearm Stall',
    );
    final challenge = ClassChallenge(
      id: 'forearm-stall-shaker',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      teacherDisplayName: 'Coach',
      title: 'Forearm Stall challenge',
      description: 'Hold the stall cleanly.',
      movementName: movement.name,
      difficulty: movement.difficulty,
      prop: TrainingProp.shaker,
      startAt: DateTime.utc(2026, 9, 1),
      deadline: DateTime.utc(2026, 10, 1),
    );

    await _pumpTeacherPane(
      tester,
      const Size(1440, 900),
      repository: _FakeClassChallengeRepository(challenges: [challenge]),
    );

    final artwork = find.byKey(
      const Key('class_challenge_movement_image_forearm-stall-shaker'),
    );
    expect(artwork, findsOneWidget);
    final movementImage = tester.widget<MovementImage>(artwork);
    expect(movementImage.movementName, challenge.movementName);
    expect(movementImage.prop, challenge.prop);
    expect(
      find.descendant(
        of: find.byKey(const Key('class_challenge_card_forearm-stall-shaker')),
        matching: find.byType(MovementImage),
      ),
      findsOneWidget,
    );
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
    expect(find.text('Attempts'), findsOneWidget);
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
      tester
          .getSize(find.byKey(const Key('class_challenge_cancel_action')))
          .height,
      tester
          .getSize(find.byKey(const Key('class_challenge_primary_action')))
          .height,
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
    expect(
      find.byKey(const Key('class_challenge_specific_times_toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('class_challenge_start_hour')), findsNothing);
    expect(
      find.byKey(const Key('class_challenge_deadline_hour')),
      findsNothing,
    );
    expect(find.byType(DatePicker), findsNWidgets(2));
    tester
        .widget<ToggleSwitch>(
          find.byKey(const Key('class_challenge_specific_times_toggle')),
        )
        .onChanged!(true);
    await tester.pump();
    final startHour = tester.widget<ComboBox<int>>(
      find.byKey(const Key('class_challenge_start_hour')),
    );
    expect(startHour.items!.map((item) => item.value), containsAll([1, 12]));
    expect(startHour.items!.map((item) => item.value), isNot(contains(0)));
    expect(startHour.items!.map((item) => item.value), isNot(contains(13)));
    for (final key in const [
      Key('class_challenge_start_minute'),
      Key('class_challenge_deadline_minute'),
    ]) {
      final minuteBox = tester.widget<ComboBox<int>>(find.byKey(key));
      expect(
        minuteBox.items!.map((item) => item.value),
        orderedEquals(List<int>.generate(60, (index) => index)),
      );
      for (final minute in [7, 23, 59]) {
        final item = minuteBox.items!.singleWhere(
          (item) => item.value == minute,
        );
        expect(item.child, isA<Text>());
        expect((item.child as Text).data, minute.toString().padLeft(2, '0'));
      }
    }
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('class_challenge_start_minute')),
        )
        .onChanged!(7);
    await tester.pump();
    tester
        .widget<ToggleSwitch>(
          find.byKey(const Key('class_challenge_specific_times_toggle')),
        )
        .onChanged!(false);
    await tester.pump();
    expect(find.byKey(const Key('class_challenge_start_minute')), findsNothing);
    tester
        .widget<ToggleSwitch>(
          find.byKey(const Key('class_challenge_specific_times_toggle')),
        )
        .onChanged!(true);
    await tester.pump();
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('class_challenge_start_minute')),
          )
          .value,
      7,
    );
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

  testWidgets('Shad schedule uses only its two time pickers', (tester) async {
    await _pumpTeacherPane(tester, const Size(1440, 900), shadTheme: true);
    await tester.tap(find.byKey(const Key('class_challenge_create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('class_challenge_start_time')), findsNothing);
    expect(
      find.byKey(const Key('class_challenge_deadline_time')),
      findsNothing,
    );
    tester
        .widget<shad.ShadSwitch>(
          find.byKey(const Key('class_challenge_specific_times_toggle')),
        )
        .onChanged!(true);
    await tester.pumpAndSettle();

    expect(find.byType(shad.ShadTimePicker), findsNWidgets(2));
    expect(find.byKey(const Key('class_challenge_start_time')), findsOneWidget);
    expect(
      find.byKey(const Key('class_challenge_deadline_time')),
      findsOneWidget,
    );
    expect(find.byType(ComboBox<int>), findsNothing);
    expect(find.byType(ComboBox<String>), findsNothing);
    expect(tester.takeException(), isNull);
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
    expect(
      find.byKey(const Key('class_challenge_movement_preview')),
      findsOneWidget,
    );
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
    expect(
      classChallengeDateTimeFrom12Hour(base, hour: 9, minute: 7, period: 'AM'),
      DateTime(2026, 9, 11, 9, 7),
    );
    expect(
      classChallengeDateTimeFrom12Hour(base, hour: 1, minute: 23, period: 'PM'),
      DateTime(2026, 9, 11, 13, 23),
    );
    expect(
      classChallengeDateTimeFrom12Hour(
        base,
        hour: 11,
        minute: 59,
        period: 'PM',
      ),
      DateTime(2026, 9, 11, 23, 59),
    );
  });

  test('date-only boundaries accept a same-day challenge', () {
    final date = DateTime(2026, 9, 11, 14, 23);
    final start = classChallengeStartOfDay(date);
    final deadline = classChallengeEndOfDay(date);

    expect(start, DateTime(2026, 9, 11));
    expect(deadline, DateTime(2026, 9, 11, 23, 59));
    expect(deadline.isAfter(start), isTrue);
    expect(
      classChallengeUsesDateOnlyBoundaries(start: start, deadline: deadline),
      isTrue,
    );
  });

  testWidgets('date-only scheduling persists selected date boundaries', (
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
        .widget<DatePicker>(find.byKey(const Key('class_challenge_start_date')))
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

    await tester.tap(find.text('Create Challenge'));
    await tester.pumpAndSettle();

    expect(repository.createdChallenge, isNotNull);
    expect(
      repository.createdChallenge!.startAt,
      DateTime(startDate.year, startDate.month, startDate.day).toUtc(),
    );
    expect(
      repository.createdChallenge!.deadline,
      DateTime(deadline.year, deadline.month, deadline.day, 23, 59).toUtc(),
    );
  });

  testWidgets('specific times preserve selected 12-hour minutes as UTC', (
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
        .widget<DatePicker>(find.byKey(const Key('class_challenge_start_date')))
        .selected!;
    tester
        .widget<ToggleSwitch>(
          find.byKey(const Key('class_challenge_specific_times_toggle')),
        )
        .onChanged!(true);
    await tester.pump();
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
        .onChanged!(23);
    await tester.pump();
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('class_challenge_start_period')),
        )
        .onChanged!('PM');
    await tester.pump();
    await tester.tap(find.text('Create Challenge'));
    await tester.pumpAndSettle();

    expect(
      repository.createdChallenge!.startAt,
      DateTime(startDate.year, startDate.month, startDate.day, 17, 23).toUtc(),
    );
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
    final repository = _FakeClassChallengeRepository(challenges: [challenge]);
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
      find.textContaining(
        'Existing attempts and leaderboard results will be kept.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Assessment V2'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(repository.archivedChallengeId, 'challenge-archive');
  });

  testWidgets(
    'Teacher permanently deletes a challenge after typed confirmation',
    (tester) async {
      final challenge = ClassChallenge(
        id: 'challenge-delete',
        groupId: 'group-1',
        teacherId: 'teacher-1',
        teacherDisplayName: 'Coach',
        title: 'Delete me',
        description: 'Complete a clean toss.',
        movementName: movementCatalog.first.name,
        difficulty: movementCatalog.first.difficulty,
        prop: TrainingProp.bottle,
        startAt: DateTime.utc(2026, 9, 10, 9),
        deadline: DateTime.utc(2026, 9, 18, 17),
      );
      final repository = _FakeClassChallengeRepository(challenges: [challenge]);
      await _pumpTeacherPane(
        tester,
        const Size(1440, 900),
        repository: repository,
      );

      await tester.tap(
        find.byKey(const Key('class_challenge_delete_challenge-delete')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete challenge permanently?'), findsOneWidget);
      expect(
        find.textContaining(
          'participant, attempt, and leaderboard data will be permanently removed',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('class_challenge_delete_confirmation')),
        'DELETE CHALLENGE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('class_challenge_confirm_delete')));
      await tester.pumpAndSettle();

      expect(repository.permanentDeleteCalls, 1);
      expect(repository.permanentlyDeletedChallengeId, challenge.id);
    },
  );

  testWidgets(
    'challenge deletion prevents double-submit and keeps failure actionable',
    (tester) async {
      final challenge = ClassChallenge(
        id: 'challenge-delete-failure',
        groupId: 'group-1',
        teacherId: 'teacher-1',
        teacherDisplayName: 'Coach',
        title: 'Keep on failure',
        description: 'Complete a clean toss.',
        movementName: movementCatalog.first.name,
        difficulty: movementCatalog.first.difficulty,
        prop: TrainingProp.bottle,
        startAt: DateTime.utc(2026, 9, 10, 9),
        deadline: DateTime.utc(2026, 9, 18, 17),
      );
      final repository = _FakeClassChallengeRepository(challenges: [challenge])
        ..permanentDeleteGate = Completer<void>();
      await _pumpTeacherPane(
        tester,
        const Size(1440, 900),
        repository: repository,
      );
      await tester.tap(
        find.byKey(
          const Key('class_challenge_delete_challenge-delete-failure'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('class_challenge_delete_confirmation')),
        'DELETE CHALLENGE',
      );
      await tester.pump();
      final confirm = find.byKey(const Key('class_challenge_confirm_delete'));
      final submit = tester.widget<ElixPrimaryButton>(confirm).onPressed!;
      submit();
      submit();
      await tester.pump();

      expect(repository.permanentDeleteCalls, 1);
      expect(tester.widget<ElixPrimaryButton>(confirm).onPressed, isNull);

      repository.permanentDeleteError = const ClassChallengeException(
        'offline',
      );
      repository.permanentDeleteGate!.complete();
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not delete this challenge. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('class_challenge_card_${challenge.id}')),
        findsOneWidget,
      );
    },
  );

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
  bool shadTheme = false,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(
        content: shadTheme
            ? ElixShadThemeBridge(
                child: ClassChallengesPane(
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
              )
            : ClassChallengesPane(
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
