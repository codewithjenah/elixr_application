import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/movement_mastery.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/core/constants/movement_mastery_rules.dart';
import 'package:elixr_application/features/movements/movements_presentation.dart';
import 'package:elixr_application/features/movements/widgets/movement_card.dart';
import 'package:elixr_application/features/movements/widgets/movement_difficulty_section.dart';
import 'package:elixr_application/features/movements/widgets/movements_header.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return FluentApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: ScaffoldPage(content: child),
  );
}

Widget wrapWithRouter({
  required GoRouter router,
  Brightness brightness = Brightness.dark,
}) {
  return FluentApp.router(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    routeInformationParser: router.routeInformationParser,
    routerDelegate: router.routerDelegate,
    routeInformationProvider: router.routeInformationProvider,
  );
}

GoRouter practiceTrackingRouter({
  required Widget home,
  required List<String> navigatedLocations,
}) {
  return GoRouter(
    initialLocation: '/movements',
    routes: [
      GoRoute(path: '/movements', builder: (context, state) => home),
      GoRoute(
        path: '/practice',
        builder: (context, state) {
          navigatedLocations.add(state.uri.toString());
          return const ScaffoldPage(
            content: Center(child: Text('Practice screen')),
          );
        },
      ),
    ],
  );
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> expectNoOverflow(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

const easyMovement = Movement(
  name: 'Normal Grip',
  difficulty: 'Easy',
  description: 'Hold the bottle with a standard overhand grip.',
  requiresHandsDetection: true,
  enabled: true,
);

const secondEasyMovement = Movement(
  name: "Bartender's Grip",
  difficulty: 'Easy',
  description: 'Pinch the neck with thumb and index finger.',
  requiresHandsDetection: true,
  enabled: true,
);

const thirdEasyMovement = Movement(
  name: 'Reverse Grip',
  difficulty: 'Easy',
  description: 'Hold the bottle with an underhand grip.',
  requiresHandsDetection: true,
  enabled: true,
);

const fourthEasyMovement = Movement(
  name: 'Claw Grip',
  difficulty: 'Easy',
  description:
      'Hold the upright bottle from above with curled fingers around the upper neck.',
  requiresHandsDetection: true,
  enabled: true,
);

const disabledMovement = Movement(
  name: 'Locked Stall',
  difficulty: 'Hard',
  description: 'A future advanced movement.',
  requiresHandsDetection: false,
  enabled: false,
);

const mediumMovement = Movement(
  name: 'Hand Stall',
  difficulty: 'Medium',
  description: 'Balance the bottle on your open palm.',
  requiresHandsDetection: true,
  enabled: true,
  supportedProps: [TrainingProp.bottle, TrainingProp.shaker],
);

const hardMovement = Movement(
  name: 'Shoulder Stall',
  difficulty: 'Hard',
  description: 'Balance the bottle steadily on either shoulder.',
  requiresHandsDetection: true,
  enabled: true,
);

const bottleInATinMovement = Movement(
  name: 'Bottle in a tin',
  difficulty: 'Hard',
  description:
      'Balance an upright bottle steadily on a horizontally held cocktail shaker.',
  requiresHandsDetection: true,
  enabled: true,
  supportedProps: [TrainingProp.bottleAndShaker],
);

MovementMastery masteryFor(
  Movement movement, {
  List<Session> sessions = const [],
}) {
  final built = buildMovementMasteries(
    sessions: sessions,
    movements: [movement],
  );
  if (built.isNotEmpty) return built.first;

  final noviceReq = requirementForLevel(MovementMasteryLevel.novice);
  return MovementMastery(
    movement: movement,
    catalogIndex: 0,
    level: MovementMasteryLevel.unpracticed,
    masteryPoints: 0,
    completedSessions: 0,
    lifetimeAverageScore: null,
    recentAverageScore: null,
    previousRecentAverageScore: null,
    bestScore: null,
    scoreTrend: ScoreTrend.unknown,
    lastPracticedAt: null,
    progressToNextLevel: 0,
    grandmasterProgress: 0,
    sessionsRemaining: noviceReq.minSessions,
    masteryPointsRemaining: noviceReq.minMasteryPoints,
    nextLevel: MovementMasteryLevel.novice,
  );
}

Session practiceSession(
  Movement movement, {
  int score = 70,
  String? createdAt,
}) {
  return Session(
    userId: 'user-1',
    movementName: movement.name,
    difficulty: movement.difficulty,
    score: score,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

Map<String, MovementMastery> masteryMap(List<MovementMastery> masteries) {
  return {for (final m in masteries) normalizeMovementName(m.movement.name): m};
}

void main() {
  group('MovementsHeader', () {
    testWidgets('shows practiced, sessions, and weighted average labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MovementsHeader(
            summary: MovementsSummary(
              practicedCount: 3,
              totalMovements: 9,
              totalSessions: 6,
              overallAverage: 84,
              overallMasteryProgress: 0.33,
              totalMasteryPoints: 120,
              grandmasterCount: 0,
            ),
          ),
        ),
      );

      expect(find.text('Movements'), findsOneWidget);
      expect(
        find.text(
          'Build your flair foundation, balance, and advanced control.',
        ),
        findsOneWidget,
      );
      expect(find.text('3 of 9'), findsOneWidget);
      expect(find.text('6'), findsWidgets);
      expect(find.text('84%'), findsOneWidget);
      expect(find.text('33%'), findsWidgets);
      expect(find.textContaining('Best avg'), findsNothing);
    });

    testWidgets('shows no-score state when average is null', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MovementsHeader(
            summary: MovementsSummary(
              practicedCount: 0,
              totalMovements: 9,
              totalSessions: 0,
              overallAverage: null,
              overallMasteryProgress: 0,
              totalMasteryPoints: 0,
              grandmasterCount: 0,
            ),
          ),
        ),
      );

      expect(find.text('No score yet'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
    });
  });

  group('MovementCard', () {
    testWidgets('shows new state for unpracticed movement', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 900,
            child: MovementCard(mastery: masteryFor(easyMovement)),
          ),
        ),
      );

      expect(find.text('Lv. 0 · Unpracticed'), findsOneWidget);
      expect(find.text('Start your Novice path'), findsWidgets);
      expect(find.text('Start practice'), findsOneWidget);
      expect(find.text('Hands tracking'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
      expect(find.textContaining('Average score'), findsNothing);
    });

    testWidgets('shows average score and practice-again for practiced', (
      tester,
    ) async {
      final mastery = masteryFor(
        easyMovement,
        sessions: [
          practiceSession(
            easyMovement,
            score: 84,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
          practiceSession(
            easyMovement,
            score: 84,
            createdAt: '2026-01-02T00:00:00.000Z',
          ),
        ],
      );

      await tester.pumpWidget(
        wrap(SizedBox(width: 900, child: MovementCard(mastery: mastery))),
      );

      expect(find.text('Practice again'), findsOneWidget);
      expect(find.textContaining('mastery pts'), findsOneWidget);
      expect(find.textContaining('Lv.'), findsOneWidget);
      expect(find.textContaining('Recent'), findsOneWidget);
      expect(find.textContaining('Best'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
      expect(find.textContaining('Average score'), findsNothing);
      expect(find.text('Practiced'), findsNothing);
    });

    testWidgets('wide desktop layout does not overflow', (tester) async {
      await setSurface(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 1200,
            child: MovementCard(
              mastery: masteryFor(
                easyMovement,
                sessions: [
                  practiceSession(easyMovement, score: 100),
                  practiceSession(easyMovement, score: 100),
                ],
              ),
            ),
          ),
        ),
      );

      await expectNoOverflow(tester);
      expect(find.text('Practice again'), findsOneWidget);
    });

    testWidgets('narrow layout does not overflow', (tester) async {
      await setSurface(tester, const Size(400, 800));
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 360,
            child: MovementCard(
              mastery: masteryFor(
                easyMovement,
                sessions: [
                  practiceSession(easyMovement, score: 100),
                  practiceSession(easyMovement, score: 100),
                ],
              ),
            ),
          ),
        ),
      );

      await expectNoOverflow(tester);
      expect(find.text('Practice again'), findsOneWidget);
    });

    testWidgets('shows locked state without activation affordance text', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 900,
            child: MovementCard(mastery: masteryFor(disabledMovement)),
          ),
        ),
      );

      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Locked'), findsWidgets);
      expect(find.text('Start practice'), findsNothing);
      expect(find.text('Practice again'), findsNothing);
    });

    testWidgets('Medium card shows inline Bottle and Cocktail Shaker actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 900,
            child: MovementCard(mastery: masteryFor(mediumMovement)),
          ),
        ),
      );

      expect(find.text('Practice with'), findsOneWidget);
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Cocktail Shaker'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Start practice'), findsNothing);
      expect(find.text('Practice again'), findsNothing);
      expect(
        find.text('Choose the prop you want to practice with.'),
        findsNothing,
      );
    });

    testWidgets('Medium Bottle navigates without showing prop dialog', (
      tester,
    ) async {
      final navigated = <String>[];
      late final GoRouter router;
      router = practiceTrackingRouter(
        home: ScaffoldPage(
          content: SizedBox(
            width: 900,
            child: MovementCard(mastery: masteryFor(mediumMovement)),
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(wrapWithRouter(router: router));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose the prop you want to practice with.'),
        findsNothing,
      );

      await tester.tap(find.text('Bottle'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose the prop you want to practice with.'),
        findsNothing,
      );
      expect(find.text('Practice screen'), findsOneWidget);
      expect(navigated, hasLength(1));
      expect(navigated.single, contains('movement=Hand%20Stall'));
      expect(navigated.single, contains('difficulty=Medium'));
      expect(navigated.single, contains('prop=bottle'));
    });

    testWidgets('Medium Cocktail Shaker is enabled and navigates with shaker', (
      tester,
    ) async {
      final navigated = <String>[];
      late final GoRouter router;
      router = practiceTrackingRouter(
        home: ScaffoldPage(
          content: SizedBox(
            width: 900,
            child: MovementCard(
              mastery: masteryFor(
                mediumMovement,
                sessions: [practiceSession(mediumMovement, score: 70)],
              ),
            ),
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(wrapWithRouter(router: router));
      await tester.pumpAndSettle();

      final shakerSemantics = tester.getSemantics(find.text('Cocktail Shaker'));
      expect(shakerSemantics.flagsCollection.isEnabled.toBoolOrNull(), isTrue);

      await tester.tap(find.text('Cocktail Shaker'));
      await tester.pumpAndSettle();

      expect(navigated, hasLength(1));
      expect(navigated.single, contains('movement=Hand%20Stall'));
      expect(navigated.single, contains('difficulty=Medium'));
      expect(navigated.single, contains('prop=shaker'));
      expect(find.text('Practice screen'), findsOneWidget);
    });

    testWidgets('Bottle in a tin shows a fixed Bottle + Shaker action', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 900,
            child: MovementCard(mastery: masteryFor(bottleInATinMovement)),
          ),
        ),
      );

      expect(find.text('Start with Bottle + Cocktail Shaker'), findsOneWidget);
      expect(find.text('Practice with'), findsNothing);
      expect(find.text('Choose a prop'), findsNothing);
      expect(find.text('Start practice'), findsNothing);
      expect(find.text('Practice again'), findsNothing);
    });

    testWidgets('Bottle in a tin tap navigates with prop=bottle_and_shaker', (
      tester,
    ) async {
      final navigated = <String>[];
      late final GoRouter router;
      router = practiceTrackingRouter(
        home: ScaffoldPage(
          content: SizedBox(
            width: 900,
            child: MovementCard(
              mastery: masteryFor(
                bottleInATinMovement,
                sessions: [practiceSession(bottleInATinMovement, score: 90)],
              ),
            ),
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(wrapWithRouter(router: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start with Bottle + Cocktail Shaker'));
      await tester.pumpAndSettle();

      expect(navigated, hasLength(1));
      expect(navigated.single, contains('movement=Bottle%20in%20a%20tin'));
      expect(navigated.single, contains('difficulty=Hard'));
      expect(navigated.single, contains('prop=bottle_and_shaker'));
      expect(find.text('Practice screen'), findsOneWidget);
    });

    testWidgets('Easy and Hard cards keep a single practice CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              SizedBox(
                width: 900,
                child: MovementCard(mastery: masteryFor(easyMovement)),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  mastery: masteryFor(
                    hardMovement,
                    sessions: [
                      practiceSession(hardMovement, score: 88),
                      practiceSession(hardMovement, score: 88),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Start practice'), findsOneWidget);
      expect(find.text('Practice again'), findsOneWidget);
      expect(find.text('Practice with'), findsNothing);
      expect(find.text('Bottle'), findsNothing);
      expect(find.text('Cocktail Shaker'), findsNothing);
    });

    testWidgets('Medium compact layout does not overflow with prop actions', (
      tester,
    ) async {
      await setSurface(tester, const Size(400, 800));
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 360,
            child: MovementCard(
              mastery: masteryFor(
                mediumMovement,
                sessions: [
                  practiceSession(mediumMovement, score: 80),
                  practiceSession(mediumMovement, score: 80),
                ],
              ),
            ),
          ),
        ),
      );

      await expectNoOverflow(tester);
      expect(find.text('Practice with'), findsOneWidget);
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Cocktail Shaker'), findsOneWidget);
    });
  });

  group('MovementDifficultySection', () {
    testWidgets('renders four movements as vertical rows', (tester) async {
      await setSurface(tester, const Size(1280, 1200));
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 1200,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              movements: const [
                easyMovement,
                secondEasyMovement,
                thirdEasyMovement,
                fourthEasyMovement,
              ],
              masteryByName: masteryMap([
                masteryFor(
                  easyMovement,
                  sessions: [practiceSession(easyMovement, score: 70)],
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Easy — Foundations'), findsOneWidget);
      expect(find.textContaining('Easy mastery'), findsOneWidget);
      expect(find.byType(MovementCard), findsNWidgets(4));
      expect(find.byType(GridView), findsNothing);

      final positions = <Offset>[];
      for (var i = 0; i < 4; i++) {
        positions.add(tester.getTopLeft(find.byType(MovementCard).at(i)));
      }

      for (var i = 1; i < positions.length; i++) {
        expect(positions[i].dx, closeTo(positions[0].dx, 1));
        expect(positions[i].dy, greaterThan(positions[i - 1].dy));
      }
    });

    testWidgets('collapses and expands movement rows', (tester) async {
      await setSurface(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 1200,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              movements: [easyMovement, secondEasyMovement],
              masteryByName: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MovementCard), findsNWidgets(2));

      final transitionFinder = find.descendant(
        of: find.byType(MovementDifficultySection),
        matching: find.byType(SizeTransition),
      );

      await tester.tap(find.text('Easy — Foundations'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(tester.getSize(transitionFinder).height, lessThan(8));

      await tester.tap(find.text('Easy — Foundations'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(tester.getSize(transitionFinder).height, greaterThan(80));
    });

    testWidgets('section practiced count remains correct', (tester) async {
      await tester.pumpWidget(
        wrap(
          MovementDifficultySection(
            difficulty: 'Medium',
            movements: const [
              easyMovement,
              secondEasyMovement,
              thirdEasyMovement,
            ],
            masteryByName: masteryMap([
              masteryFor(
                easyMovement,
                sessions: [
                  practiceSession(
                    easyMovement,
                    score: 80,
                    createdAt: '2026-01-01T00:00:00.000Z',
                  ),
                  practiceSession(
                    easyMovement,
                    score: 80,
                    createdAt: '2026-01-02T00:00:00.000Z',
                  ),
                ],
              ),
              masteryFor(
                secondEasyMovement,
                sessions: [practiceSession(secondEasyMovement, score: 70)],
              ),
            ]),
          ),
        ),
      );

      expect(find.text('Medium — Balance and control'), findsOneWidget);
      expect(find.textContaining('Medium mastery'), findsOneWidget);
    });
  });

  group('theme readability', () {
    testWidgets('header and cards render in light theme', (tester) async {
      final cardMastery = masteryFor(
        easyMovement,
        sessions: [
          practiceSession(easyMovement, score: 75),
          practiceSession(easyMovement, score: 75),
        ],
      );

      await tester.pumpWidget(
        wrap(
          brightness: Brightness.light,
          Column(
            children: [
              const MovementsHeader(
                summary: MovementsSummary(
                  practicedCount: 1,
                  totalMovements: 9,
                  totalSessions: 2,
                  overallAverage: 75,
                  overallMasteryProgress: 0.12,
                  totalMasteryPoints: 34,
                  grandmasterCount: 0,
                ),
              ),
              SizedBox(width: 900, child: MovementCard(mastery: cardMastery)),
            ],
          ),
        ),
      );

      expect(find.text('75%'), findsOneWidget);
      expect(find.textContaining('mastery pts'), findsOneWidget);
      expect(find.textContaining('Lv.'), findsOneWidget);
    });

    testWidgets('header and cards render in dark theme', (tester) async {
      final cardMastery = masteryFor(
        easyMovement,
        sessions: [
          practiceSession(easyMovement, score: 75),
          practiceSession(easyMovement, score: 75),
        ],
      );

      await tester.pumpWidget(
        wrap(
          brightness: Brightness.dark,
          Column(
            children: [
              const MovementsHeader(
                summary: MovementsSummary(
                  practicedCount: 1,
                  totalMovements: 9,
                  totalSessions: 2,
                  overallAverage: 75,
                  overallMasteryProgress: 0.12,
                  totalMasteryPoints: 34,
                  grandmasterCount: 0,
                ),
              ),
              SizedBox(width: 900, child: MovementCard(mastery: cardMastery)),
            ],
          ),
        ),
      );

      expect(find.text('75%'), findsOneWidget);
      expect(find.textContaining('mastery pts'), findsOneWidget);
      expect(find.textContaining('Lv.'), findsOneWidget);
    });
  });
}
