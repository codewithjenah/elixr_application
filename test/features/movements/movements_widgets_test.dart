import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
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
              rubricSessionCount: 6,
              overallAverageRubric: 10.5,
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
      expect(find.text('Overall rubric average'), findsOneWidget);
      expect(find.text('10.5 / 12'), findsOneWidget);
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
              rubricSessionCount: 0,
              overallAverageRubric: null,
            ),
          ),
        ),
      );

      expect(find.text('No rubric result yet'), findsOneWidget);
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
              averageRubricTotal: null,
            ),
          ),
        ),
      );

      expect(find.text('New'), findsOneWidget);
      expect(find.text('Ready to learn'), findsOneWidget);
      expect(find.text('Start practice'), findsOneWidget);
      expect(find.text('Hands tracking'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
      expect(find.textContaining('Average rubric'), findsNothing);
    });

    testWidgets('shows average rubric and practice-again for practiced', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              averageRubricTotal: 8.4,
            ),
          ),
        ),
      );

      expect(find.text('Practiced'), findsOneWidget);
      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.text('Average rubric 8 / 12'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Practice again'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
    });

    testWidgets('legacy-only movement shows no rubric result', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 3,
              averageRubricTotal: null,
            ),
          ),
        ),
      );

      expect(find.text('Practiced'), findsOneWidget);
      expect(find.text('3 sessions'), findsOneWidget);
      expect(find.text('No rubric result yet'), findsOneWidget);
      expect(find.textContaining('Average rubric'), findsNothing);
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
              averageRubricTotal: 12,
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
              averageRubricTotal: 12,
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
              averageRubricTotal: null,
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
              averageRubricTotal: null,
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
              averageRubricTotal: null,
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
              averageRubricTotal: 8,
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
          const SizedBox(
            width: 900,
            child: MovementCard(
              movement: bottleInATinMovement,
              sessionCount: 0,
              averageRubricTotal: null,
            ),
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
          content: const SizedBox(
            width: 900,
            child: MovementCard(
              movement: bottleInATinMovement,
              sessionCount: 1,
              averageRubricTotal: 11,
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
      await setSurface(tester, const Size(900, 1000));
      await tester.pumpWidget(
        wrap(
          Column(
            children: const [
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 0,
                  averageRubricTotal: null,
                ),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: hardMovement,
                  sessionCount: 2,
                  averageRubricTotal: 10,
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
              averageRubricTotal: 9,
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
    testWidgets('renders three columns at desktop width', (tester) async {
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
              stats: {
                'Normal Grip': (
                  count: 1,
                  rubricSessionCount: 1,
                  averageRubricTotal: 8,
                ),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Easy — Foundations'), findsOneWidget);
      expect(find.text('1 of 4 practiced'), findsOneWidget);
      expect(find.byType(MovementCard), findsNWidgets(4));
      expect(find.byType(GridView), findsNothing);

      final first = find.ancestor(
        of: find.text('Normal Grip'),
        matching: find.byType(MovementCard),
      );
      final second = find.ancestor(
        of: find.text("Bartender's Grip"),
        matching: find.byType(MovementCard),
      );
      final third = find.ancestor(
        of: find.text('Reverse Grip'),
        matching: find.byType(MovementCard),
      );
      final fourth = find.ancestor(
        of: find.text('Claw Grip'),
        matching: find.byType(MovementCard),
      );
      final positions = [
        tester.getTopLeft(first),
        tester.getTopLeft(second),
        tester.getTopLeft(third),
        tester.getTopLeft(fourth),
      ];

      expect(positions[0].dy, closeTo(positions[1].dy, 1));
      expect(positions[1].dy, closeTo(positions[2].dy, 1));
      expect(positions[0].dx, lessThan(positions[1].dx));
      expect(positions[1].dx, lessThan(positions[2].dx));
      expect(positions[3].dx, closeTo(positions[0].dx, 1));
      expect(positions[3].dy, greaterThan(positions[0].dy));

      expect(tester.getSize(first).height, lessThan(430));
      expect(tester.getSize(second).height, lessThan(430));
    });

    testWidgets('uses two columns from 700 through 1099 pixels', (
      tester,
    ) async {
      await setSurface(tester, const Size(1000, 1200));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              movements: [easyMovement, secondEasyMovement, thirdEasyMovement],
              stats: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.getTopLeft(
        find.ancestor(
          of: find.text('Normal Grip'),
          matching: find.byType(MovementCard),
        ),
      );
      final second = tester.getTopLeft(
        find.ancestor(
          of: find.text("Bartender's Grip"),
          matching: find.byType(MovementCard),
        ),
      );
      final third = tester.getTopLeft(
        find.ancestor(
          of: find.text('Reverse Grip'),
          matching: find.byType(MovementCard),
        ),
      );
      expect(first.dy, closeTo(second.dy, 1));
      expect(first.dx, lessThan(second.dx));
      expect(third.dx, closeTo(first.dx, 1));
      expect(third.dy, greaterThan(first.dy));
    });

    testWidgets('uses one column below 700 pixels', (tester) async {
      await setSurface(tester, const Size(680, 1600));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 650,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              movements: [easyMovement, secondEasyMovement, thirdEasyMovement],
              stats: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final positions = List.generate(
        3,
        (index) => tester.getTopLeft(find.byType(MovementCard).at(index)),
      );
      expect(positions[1].dx, closeTo(positions[0].dx, 1));
      expect(positions[2].dx, closeTo(positions[0].dx, 1));
      expect(positions[1].dy, greaterThan(positions[0].dy));
      expect(positions[2].dy, greaterThan(positions[1].dy));
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
      await setSurface(tester, const Size(1000, 1200));
      await tester.pumpWidget(
        wrap(
          const MovementDifficultySection(
            difficulty: 'Medium',
            movements: [easyMovement, secondEasyMovement, thirdEasyMovement],
            stats: {
              'Normal Grip': (
                count: 2,
                rubricSessionCount: 2,
                averageRubricTotal: 9,
              ),
              "Bartender's Grip": (
                count: 1,
                rubricSessionCount: 1,
                averageRubricTotal: 8,
              ),
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
                  rubricSessionCount: 2,
                  overallAverageRubric: 9,
                ),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 2,
                  averageRubricTotal: 9,
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('9.0 / 12'), findsOneWidget);
      expect(find.text('Average rubric 9 / 12'), findsOneWidget);
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
                  rubricSessionCount: 2,
                  overallAverageRubric: 9,
                ),
              ),
              SizedBox(
                width: 900,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 2,
                  averageRubricTotal: 9,
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.text('9.0 / 12'), findsOneWidget);
      expect(find.text('Average rubric 9 / 12'), findsOneWidget);
    });
  });
}
