import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/movement.dart';
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
);

const hardMovement = Movement(
  name: 'Shoulder Stall',
  difficulty: 'Hard',
  description: 'Balance the bottle steadily on either shoulder.',
  requiresHandsDetection: true,
  enabled: true,
);

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
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 0,
              avgScore: 0,
            ),
          ),
        ),
      );

      expect(find.text('New'), findsOneWidget);
      expect(find.text('Ready to learn'), findsOneWidget);
      expect(find.text('Start practice'), findsOneWidget);
      expect(find.text('Hands tracking'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
      expect(find.textContaining('Average score'), findsNothing);
    });

    testWidgets('shows average score and practice-again for practiced', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              avgScore: 84.4,
            ),
          ),
        ),
      );

      expect(find.text('Practiced'), findsOneWidget);
      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.text('Average score 84%'), findsOneWidget);
      expect(find.text('Practice again'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
    });

    testWidgets('wide desktop layout does not overflow', (tester) async {
      await setSurface(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 1200,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              avgScore: 100,
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
          const SizedBox(
            width: 360,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              avgScore: 100,
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
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: disabledMovement,
              sessionCount: 0,
              avgScore: 0,
            ),
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
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: mediumMovement,
              sessionCount: 0,
              avgScore: 0,
            ),
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
          content: const SizedBox(
            width: 900,
            child: MovementCard(
              movement: mediumMovement,
              sessionCount: 0,
              avgScore: 0,
            ),
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
          content: const SizedBox(
            width: 900,
            child: MovementCard(
              movement: mediumMovement,
              sessionCount: 1,
              avgScore: 70,
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

    testWidgets('Easy and Hard cards keep a single practice CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: const [
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 0,
                  avgScore: 0,
                ),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: hardMovement,
                  sessionCount: 2,
                  avgScore: 88,
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
          const SizedBox(
            width: 360,
            child: MovementCard(
              movement: mediumMovement,
              sessionCount: 2,
              avgScore: 80,
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
          const SizedBox(
            width: 1200,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              movements: [
                easyMovement,
                secondEasyMovement,
                thirdEasyMovement,
                fourthEasyMovement,
              ],
              stats: {'Normal Grip': (count: 1, avgScore: 70)},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Easy — Foundations'), findsOneWidget);
      expect(find.text('1 of 4 practiced'), findsOneWidget);
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
              stats: {},
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
          const MovementDifficultySection(
            difficulty: 'Medium',
            movements: [easyMovement, secondEasyMovement, thirdEasyMovement],
            stats: {
              'Normal Grip': (count: 2, avgScore: 80),
              "Bartender's Grip": (count: 1, avgScore: 70),
            },
          ),
        ),
      );

      expect(find.text('Medium — Balance and control'), findsOneWidget);
      expect(find.text('2 of 3 practiced'), findsOneWidget);
    });
  });

  group('theme readability', () {
    testWidgets('header and cards render in light theme', (tester) async {
      await tester.pumpWidget(
        wrap(
          brightness: Brightness.light,
          Column(
            children: const [
              MovementsHeader(
                summary: MovementsSummary(
                  practicedCount: 1,
                  totalMovements: 9,
                  totalSessions: 2,
                  overallAverage: 75,
                ),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 2,
                  avgScore: 75,
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Average score 75%'), findsOneWidget);
    });

    testWidgets('header and cards render in dark theme', (tester) async {
      await tester.pumpWidget(
        wrap(
          brightness: Brightness.dark,
          Column(
            children: const [
              MovementsHeader(
                summary: MovementsSummary(
                  practicedCount: 1,
                  totalMovements: 9,
                  totalSessions: 2,
                  overallAverage: 75,
                ),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 2,
                  avgScore: 75,
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Average score 75%'), findsOneWidget);
    });
  });
}
