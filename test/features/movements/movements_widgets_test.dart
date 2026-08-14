import 'dart:ui';

import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/movements/movements_presentation.dart';
import 'package:elixr_application/features/movements/widgets/movement_card.dart';
import 'package:elixr_application/features/movements/widgets/movement_difficulty_section.dart';
import 'package:elixr_application/features/movements/widgets/movements_header.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget wrap(
  Widget child, {
  Brightness brightness = Brightness.dark,
  bool highContrast = false,
  bool disableAnimations = false,
}) {
  final theme = highContrast
      ? (brightness == Brightness.dark
            ? AppTheme.highContrastDark
            : AppTheme.highContrastLight)
      : (brightness == Brightness.dark ? AppTheme.dark : AppTheme.light);
  return FluentApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
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
      expect(find.text('TRAINING LIBRARY'), findsOneWidget);
      expect(
        find.text(
          'Build your flair foundation, sharpen your control, and master every level.',
        ),
        findsOneWidget,
      );
      expect(find.text('3 of 9'), findsOneWidget);
      expect(find.text('6'), findsWidgets);
      expect(find.text('Rubric average'), findsOneWidget);
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
            width: 1050,
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

    testWidgets('hover reveals metadata without changing card dimensions', (
      tester,
    ) async {
      await setSurface(tester, const Size(1000, 800));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            height: 430,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              averageRubricTotal: 8,
            ),
          ),
        ),
      );

      final card = find.byType(MovementCard);
      final metadata = find.descendant(
        of: card,
        matching: find.byType(AnimatedOpacity),
      );
      final initialHeight = tester.getSize(card).height;
      expect(tester.widget<AnimatedOpacity>(metadata).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedOpacity>(metadata).opacity, 1);
      expect(tester.getSize(card).height, initialHeight);
      await mouse.removePointer();
    });

    testWidgets('keyboard focus reveals metadata and Enter keeps navigation', (
      tester,
    ) async {
      final navigated = <String>[];
      final router = practiceTrackingRouter(
        home: ScaffoldPage(
          content: const SizedBox(
            width: 900,
            height: 430,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 1,
              averageRubricTotal: 9,
            ),
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(wrapWithRouter(router: router));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final metadata = find.byType(AnimatedOpacity);
      expect(tester.widget<AnimatedOpacity>(metadata).opacity, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(navigated.single, contains('movement=Normal%20Grip'));
      expect(navigated.single, contains('difficulty=Easy'));
      expect(navigated.single, contains('prop=bottle'));
    });

    testWidgets('one-column cards keep metadata visible', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 600,
            height: 430,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 1,
              averageRubricTotal: 9,
            ),
          ),
        ),
      );

      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
    });

    testWidgets('reduced motion removes lift and parallax', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            height: 430,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 1,
              averageRubricTotal: 9,
            ),
          ),
          disableAnimations: true,
        ),
      );

      final card = find.byType(MovementCard);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump();

      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('movement-card-surface')),
      );
      expect(surface.duration, Duration.zero);
      expect(surface.transform!.storage[12], 0);
      expect(surface.transform!.storage[13], 0);
      expect(surface.transform!.storage[0], 1);
      await mouse.removePointer();
    });

    testWidgets('high contrast uses solid card surfaces without blur or glow', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 900,
            height: 430,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 1,
              averageRubricTotal: 9,
            ),
          ),
          highContrast: true,
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('movement-card-surface')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isEmpty);
      expect(decoration.border!.top.width, 2);
      expect(decoration.gradient, isNull);
      expect(decoration.color, isNot(AppColors.cardSurfaceHighContrastDark));
      expect(decoration.color!.a, 1);
    });

    testWidgets('difficulty gives each card a distinct tinted surface', (
      tester,
    ) async {
      await setSurface(tester, const Size(1000, 1000));
      await tester.pumpWidget(
        wrap(
          const Column(
            children: [
              SizedBox(
                width: 900,
                height: 430,
                child: MovementCard(
                  movement: easyMovement,
                  sessionCount: 0,
                  averageRubricTotal: null,
                ),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: 900,
                height: 430,
                child: MovementCard(
                  movement: hardMovement,
                  sessionCount: 0,
                  averageRubricTotal: null,
                ),
              ),
            ],
          ),
        ),
      );

      final surfaces = tester
          .widgetList<AnimatedContainer>(
            find.byKey(const ValueKey('movement-card-surface')),
          )
          .map((surface) => surface.decoration! as BoxDecoration)
          .toList();
      expect(surfaces, hasLength(2));
      expect(surfaces[0].gradient, isA<LinearGradient>());
      expect(surfaces[1].gradient, isA<LinearGradient>());
      final easyColor = (surfaces[0].gradient! as LinearGradient).colors.first;
      final hardColor = (surfaces[1].gradient! as LinearGradient).colors.first;
      expect(easyColor, isNot(hardColor));
      expect(easyColor, isNot(AppColors.cardSurface));
      expect(hardColor, isNot(AppColors.cardSurface));
    });
  });

  group('MovementDifficultySection', () {
    testWidgets('renders three equal-height columns at desktop width', (
      tester,
    ) async {
      await setSurface(tester, const Size(1280, 1200));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 1050,
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

      final banner = find.byKey(const ValueKey('difficulty-banner'));

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
      expect(
        positions[0].dy - tester.getRect(banner).bottom,
        greaterThanOrEqualTo(30),
      );

      final cardHeights = [
        first,
        second,
        third,
        fourth,
      ].map((finder) => tester.getSize(finder).height).toList();
      expect(cardHeights.first, 448);
      for (final height in cardHeights.skip(1)) {
        expect(height, closeTo(cardHeights.first, 1));
      }
      expect(
        positions[3].dy - (positions[0].dy + cardHeights.first),
        closeTo(32, 1),
      );
    });

    testWidgets('uses two columns from 680 through 1049 pixels', (
      tester,
    ) async {
      await setSurface(tester, const Size(1200, 1200));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 1049,
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
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text('Normal Grip'),
                matching: find.byType(MovementCard),
              ),
            )
            .height,
        closeTo(
          tester
              .getSize(
                find.ancestor(
                  of: find.text("Bartender's Grip"),
                  matching: find.byType(MovementCard),
                ),
              )
              .height,
          1,
        ),
      );
      expect(third.dx, closeTo(first.dx, 1));
      expect(third.dy, greaterThan(first.dy));
    });

    testWidgets('multi-prop cards fit the three-column reserved height', (
      tester,
    ) async {
      await setSurface(tester, const Size(1200, 1200));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 1120,
            child: MovementDifficultySection(
              difficulty: 'Medium',
              movements: [mediumMovement, mediumMovement, mediumMovement],
              stats: {},
            ),
          ),
        ),
      );

      await expectNoOverflow(tester);
      for (final card in find.byType(MovementCard).evaluate()) {
        expect((card.renderObject! as RenderBox).size.height, 448);
      }
    });

    testWidgets('hovered edge cards stay inside the grid gutter', (
      tester,
    ) async {
      await setSurface(tester, const Size(1280, 1000));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 1050,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              movements: [easyMovement, secondEasyMovement, thirdEasyMovement],
              stats: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstCard = find.byType(MovementCard).first;
      final grid = find.byKey(const ValueKey('movement-grid'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(firstCard));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(firstCard).left,
        greaterThanOrEqualTo(tester.getRect(grid).left),
      );
      await mouse.removePointer();
    });

    testWidgets('uses one column below 680 pixels', (tester) async {
      await setSurface(tester, const Size(670, 1600));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 679,
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
