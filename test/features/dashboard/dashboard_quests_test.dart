import 'dart:async';

import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/utils/manila_day.dart';
import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:elixr_application/data/models/daily_quest_board.dart';
import 'package:elixr_application/data/models/quest_claim.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/gamification_repository.dart';
import 'package:elixr_application/features/dashboard/dashboard_quests.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_quest_card.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

final _dayStart = DateTime.utc(2026, 8, 3, 16, 0, 0); // Manila 2026-08-04 00:00
const _insideWindow = '2026-08-04T03:00:00.000Z';
const _outsideWindow = '2026-08-02T03:00:00.000Z';

// 2 easy + 2 medium + 1 hard, ordered so the first 3 are one of each tier
// (mirrors what generateDailyQuestIds always produces).
final _board = DailyQuestBoard(
  userId: 'u1',
  dayKey: '20260804',
  dayStart: _dayStart,
  questIds: const [
    'two_movements', // easy (active)
    'distinct_props_2', // medium (active)
    'practice_hard_movement', // hard (active)
    'use_shaker', // easy (reserve)
    'three_movements', // medium (reserve)
  ],
);

Session _session({
  String movementName = 'Flair',
  int score = 70,
  String createdAt = _insideWindow,
  TrainingProp propType = TrainingProp.bottle,
  String difficulty = 'Easy',
}) {
  return Session(
    userId: 'u1',
    movementName: movementName,
    difficulty: difficulty,
    legacyScore: score,
    durationSeconds: 60,
    createdAt: createdAt,
    propType: propType,
  );
}

void main() {
  group('buildActiveDashboardQuests', () {
    test('returns at most 3 active quests, in board order', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: const [],
      );

      expect(quests.map((q) => q.id), [
        'two_movements',
        'distinct_props_2',
        'practice_hard_movement',
      ]);
    });

    test(
      'claiming an active quest removes it and promotes the next reserve quest',
      () {
        final quests = buildActiveDashboardQuests(
          board: _board,
          claimedQuestIds: const {'two_movements'},
          sessions: const [],
        );

        expect(quests.map((q) => q.id), [
          'distinct_props_2',
          'practice_hard_movement',
          'use_shaker',
        ]);
      },
    );

    test('claiming multiple quests keeps promoting in board order', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {'two_movements', 'distinct_props_2'},
        sessions: const [],
      );

      expect(quests.map((q) => q.id), [
        'practice_hard_movement',
        'use_shaker',
        'three_movements',
      ]);
    });

    test('returns no quests once every board quest is claimed', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: _board.questIds.toSet(),
        sessions: const [],
      );

      expect(quests, isEmpty);
    });

    test('progress reflects current/target and completion', () {
      final incomplete = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: [_session(movementName: 'Flair')],
      );
      final twoMovements = incomplete.firstWhere(
        (q) => q.id == 'two_movements',
      );
      expect(twoMovements.current, 1);
      expect(twoMovements.target, 2);
      expect(twoMovements.completed, isFalse);

      final complete = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: [
          _session(movementName: 'Flair'),
          _session(movementName: 'Spin'),
        ],
      );
      final twoMovementsDone = complete.firstWhere(
        (q) => q.id == 'two_movements',
      );
      expect(twoMovementsDone.current, 2);
      expect(twoMovementsDone.completed, isTrue);
    });

    test('sessions outside the board Manila window are ignored', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: [
          _session(movementName: 'Flair', createdAt: _outsideWindow),
          _session(movementName: 'Spin', createdAt: _outsideWindow),
        ],
      );

      final twoMovements = quests.firstWhere((q) => q.id == 'two_movements');
      expect(twoMovements.current, 0);
      expect(twoMovements.completed, isFalse);
    });

    test('xp comes from the tier, not a caller-supplied value', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: const [],
      );

      final easy = quests.firstWhere((q) => q.id == 'two_movements');
      final medium = quests.firstWhere((q) => q.id == 'distinct_props_2');
      final hard = quests.firstWhere((q) => q.id == 'practice_hard_movement');
      expect(easy.xp, 10);
      expect(medium.xp, 15);
      expect(hard.xp, 20);
    });

    test('a persisted board can still evaluate the legacy combo quest', () {
      final board = DailyQuestBoard(
        userId: 'u1',
        dayKey: '20260804',
        dayStart: _dayStart,
        questIds: const [
          'session_count_1',
          'session_count_3',
          'use_bottle_and_shaker_combo',
          'duration_10min',
          'duration_20min',
        ],
      );

      final incomplete = buildActiveDashboardQuests(
        board: board,
        claimedQuestIds: const {},
        sessions: [
          _session(movementName: 'Hand Stall', propType: TrainingProp.shaker),
        ],
      );
      final combo = incomplete.firstWhere(
        (quest) => quest.id == 'use_bottle_and_shaker_combo',
      );
      expect(combo.title, 'Complete a Bottle + Shaker Combo Session');
      expect(combo.xp, 20);
      expect(combo.completed, isFalse);

      final complete = buildActiveDashboardQuests(
        board: board,
        claimedQuestIds: const {},
        sessions: [
          _session(
            movementName: 'Bottle in a tin',
            difficulty: 'Hard',
            propType: TrainingProp.bottleAndShaker,
          ),
        ],
      );
      expect(
        complete
            .firstWhere((quest) => quest.id == 'use_bottle_and_shaker_combo')
            .completed,
        isTrue,
      );
    });
  });

  group('isDailyBoardComplete', () {
    test('is false until every quest id is claimed', () {
      expect(
        isDailyBoardComplete(board: _board, claimedQuestIds: {'two_movements'}),
        isFalse,
      );
    });

    test('is true once all 5 quest ids are claimed', () {
      expect(
        isDailyBoardComplete(
          board: _board,
          claimedQuestIds: _board.questIds.toSet(),
        ),
        isTrue,
      );
    });
  });

  group('getOrCreateDailyBoard level contract', () {
    test(
      'returns the existing same-day board after a level increase',
      () async {
        final repo = _FakeGamificationRepository();
        addTearDown(repo.dispose);
        final first = await repo.getOrCreateDailyBoard(
          userId: 'u1',
          currentLevel: 1,
        );
        final second = await repo.getOrCreateDailyBoard(
          userId: 'u1',
          currentLevel: 16,
        );
        expect(second.questIds, first.questIds);
        expect(repo.generateCalls, 1);
        expect(
          first.questIds.any((id) => questById(id)!.minimumLevel > 1),
          isFalse,
        );
      },
    );
  });

  group('DashboardQuestCard', () {
    testWidgets('shows a localized loading state until level is resolved', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService(),
      );

      expect(find.text('Loading your level…'), findsOneWidget);
      expect(find.text("Today's Quests"), findsOneWidget);
      expect(repo.getOrCreateCalls, 0);
      expect(find.text('Complete 1 Practice Session'), findsNothing);
    });

    testWidgets('Level 1 shows the next Bottle unlock and remaining XP', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Level 1'), findsOneWidget);
      expect(
        find.text("Next unlock: Bartender's Grip • Bottle"),
        findsOneWidget,
      );
      expect(find.text('250 XP remaining'), findsOneWidget);
      expect(find.text('Earn XP to unlock your next movement'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r"Level 1.*Next unlock: Bartender's Grip • Bottle"),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('View movements')).label,
        isNot(contains('Level 1')),
      );
    });

    testWidgets('a middle level shows the next shaker unlock', (tester) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(
          totalXp: GamificationRules.xpPerLevel * 5,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Level 6'), findsOneWidget);
      expect(
        find.text('Next unlock: Hand Stall • Cocktail Shaker'),
        findsOneWidget,
      );
      expect(find.text('250 XP remaining'), findsOneWidget);
    });

    testWidgets('Level 20+ shows all movement variants unlocked', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(
          totalXp: GamificationRules.xpPerLevel * 19,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Level 20'), findsOneWidget);
      expect(find.text('All movement variants unlocked'), findsOneWidget);
      expect(find.textContaining('Next unlock:'), findsNothing);
    });

    testWidgets('renders Easy/Medium/Hard, progress, and XP rewards', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('Complete 1 Practice Session'), findsOneWidget);
      expect(find.text('Practice for 20 Minutes Total'), findsOneWidget);
      expect(find.text('Reach Mastered in a Session'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);
      expect(find.text('+15 XP'), findsOneWidget);
      expect(find.text('+20 XP'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget);
    });

    testWidgets('claiming a completed quest remains functional', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);
      final session = Session(
        userId: 'u1',
        movementName: 'Normal Grip',
        difficulty: 'Easy',
        durationSeconds: 60,
        createdAt: _insideWindow,
      );

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(),
        sessions: [session],
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready to claim'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Easy quest: Complete 1 Practice Session'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('Claim')).label,
        isNot(contains('Easy quest')),
      );
      await tester.tap(find.text('Claim'));
      await tester.pumpAndSettle();

      expect(repo.claimed, contains('session_count_1'));
      expect(find.text('Complete 1 Practice Session'), findsNothing);
      expect(find.text('Complete an Easy-Difficulty Session'), findsOneWidget);
    });

    testWidgets('quest-board error and retry remain functional', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(
        board: _widgetBoard,
        throwOnCreate: true,
      );
      addTearDown(repo.dispose);

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(),
      );
      await tester.pumpAndSettle();

      expect(find.text("Could not load today's quests."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.throwOnCreate = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Complete 1 Practice Session'), findsOneWidget);
    });

    testWidgets('View movements opens the personal Movements surface', (
      tester,
    ) async {
      final repo = _FakeGamificationRepository(board: _widgetBoard);
      addTearDown(repo.dispose);
      final navigated = <String>[];

      await _pumpQuestCard(
        tester,
        repository: repo,
        progression: TraineeProgressionService.ready(),
        navigated: navigated,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('View movements'));
      await tester.pumpAndSettle();
      expect(navigated, ['/movements']);
    });
  });
}

final _widgetBoard = DailyQuestBoard(
  userId: 'u1',
  dayKey: '20260804',
  dayStart: _dayStart,
  questIds: const [
    'session_count_1',
    'duration_20min',
    'score_95',
    'practice_easy_movement',
    'sessions_above_70_x2',
  ],
);

class _FakeGamificationRepository extends GamificationRepository {
  _FakeGamificationRepository({
    DailyQuestBoard? board,
    this.throwOnCreate = false,
  }) : _board = board;

  DailyQuestBoard? _board;
  bool throwOnCreate;
  int getOrCreateCalls = 0;
  int generateCalls = 0;
  final claimed = <String>{};
  final _claimedController = StreamController<Set<String>>.broadcast();

  void dispose() {
    _claimedController.close();
  }

  @override
  Future<DailyQuestBoard> getOrCreateDailyBoard({
    required String userId,
    required int currentLevel,
    DateTime? nowUtc,
  }) async {
    getOrCreateCalls++;
    if (throwOnCreate) {
      throw StateError('board unavailable');
    }
    if (_board != null) return _board!;
    generateCalls++;
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final dayKey = ManilaDay.dayKeyFor(now);
    _board = DailyQuestBoard(
      userId: userId,
      dayKey: dayKey,
      dayStart: ManilaDay.dayStartUtcFor(now),
      questIds: generateDailyQuestIds(
        userId: userId,
        dayKey: dayKey,
        currentLevel: currentLevel,
      ),
    );
    return _board!;
  }

  @override
  Stream<Set<String>> watchClaimedQuestIds({
    required String userId,
    required String boardId,
  }) async* {
    yield {...claimed};
    yield* _claimedController.stream;
  }

  @override
  Future<QuestClaimResult> claimQuest({
    required String userId,
    required String questId,
    required List<Session> sessionsToday,
    DateTime? nowUtc,
  }) async {
    claimed.add(questId);
    _claimedController.add({...claimed});
    return QuestClaimResult.claimed(questById(questId)?.xp ?? 0);
  }
}

Future<void> _pumpQuestCard(
  WidgetTester tester, {
  required _FakeGamificationRepository repository,
  required TraineeProgressionService progression,
  List<Session> sessions = const [],
  List<String>? navigated,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => ScaffoldPage(
          content: SizedBox(
            width: 380,
            child: DashboardQuestCard(
              userId: 'u1',
              sessions: sessions,
              streakDays: 0,
              repository: repository,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/movements',
        builder: (context, state) {
          navigated?.add(state.uri.toString());
          return const ScaffoldPage(content: Text('Movements'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<TraineeProgressionService>.value(
      value: progression,
      child: FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    ),
  );
}
