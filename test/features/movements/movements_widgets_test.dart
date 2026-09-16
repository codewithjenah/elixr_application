import 'dart:ui';

import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:elixr_application/core/constants/movement_visuals.dart';
import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/movements/movements_presentation.dart';
import 'package:elixr_application/features/movements/widgets/movement_card.dart';
import 'package:elixr_application/features/movements/widgets/movement_difficulty_section.dart';
import 'package:elixr_application/features/movements/widgets/movements_header.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _CompletedTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;

  @override
  bool hasCompletedLesson(String movement, TrainingProp prop) => true;
}

class _IncompleteTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;
}

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

Widget withProgression(
  Widget child, {
  required int level,
  bool tutorialsCompleted = false,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TraineeProgressionService>(
        create: (_) => TraineeProgressionService.ready(
          totalXp: (level - 1) * GamificationRules.xpPerLevel,
        ),
      ),
      ChangeNotifierProvider<TutorialProgressService>(
        create: (_) =>
            tutorialsCompleted ? _CompletedTutorials() : _IncompleteTutorials(),
      ),
    ],
    child: child,
  );
}

Widget wrapWithProgression(
  Widget child, {
  required int level,
  bool tutorialsCompleted = false,
  bool highContrast = false,
  bool disableAnimations = false,
}) {
  return withProgression(
    wrap(
      child,
      highContrast: highContrast,
      disableAnimations: disableAnimations,
    ),
    level: level,
    tutorialsCompleted: tutorialsCompleted,
  );
}

GoRouter trackingRouter({
  required Widget home,
  required List<String> navigatedLocations,
}) {
  return GoRouter(
    initialLocation: '/movements',
    routes: [
      GoRoute(path: '/movements', builder: (_, _) => home),
      GoRoute(
        path: '/practice',
        builder: (_, state) {
          navigatedLocations.add(state.uri.toString());
          return const ScaffoldPage(content: Text('Practice screen'));
        },
      ),
      GoRoute(
        path: '/learn/movement/:name',
        builder: (_, state) {
          navigatedLocations.add(state.uri.toString());
          return const ScaffoldPage(content: Text('Lesson screen'));
        },
      ),
    ],
  );
}

Widget routerApp(GoRouter router) {
  return FluentApp.router(
    theme: AppTheme.dark,
    routeInformationParser: router.routeInformationParser,
    routerDelegate: router.routerDelegate,
    routeInformationProvider: router.routeInformationProvider,
  );
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Movement movementNamed(String name) =>
    movementCatalog.singleWhere((movement) => movement.name == name);

Widget movementCard({
  required Movement movement,
  required TrainingProp prop,
  int sessionCount = 0,
  double? averageRubricTotal,
}) {
  return SizedBox(
    width: 240,
    height: 448,
    child: MovementCard(
      movement: movement,
      prop: prop,
      sessionCount: sessionCount,
      averageRubricTotal: averageRubricTotal,
    ),
  );
}

RubricAssessment rubric(int total) {
  final scores = <int>[0, 0, 0, 0];
  var remaining = total;
  for (var index = 0; index < scores.length && remaining > 0; index++) {
    scores[index] = remaining.clamp(0, 3);
    remaining -= scores[index];
  }
  return RubricAssessment(
    technique: scores[0],
    stability: scores[1],
    completion: scores[2],
    propPositioning: scores[3],
  );
}

Session session({required TrainingProp prop, int? rubricTotal}) {
  return Session(
    userId: 'trainee-1',
    movementName: 'Hand Stall',
    difficulty: 'Medium',
    rubric: rubricTotal == null ? null : rubric(rubricTotal),
    assessmentVersion: rubricTotal == null ? 1 : 2,
    legacyScore: rubricTotal == null ? 80 : null,
    durationSeconds: 30,
    propType: prop,
  );
}

void main() {
  group('variant presentation and statistics', () {
    test('difficulty sections contain 5, 10, and 5 variants', () {
      expect(practiceStepsForDifficulty('Easy'), hasLength(5));
      expect(practiceStepsForDifficulty('Medium'), hasLength(10));
      expect(practiceStepsForDifficulty('Hard'), hasLength(5));
      expect(enabledPracticeSteps(), hasLength(20));
    });

    test('Medium variants use movement-paired presentation order', () {
      final variants = practiceStepsForDifficulty('Medium')
          .map((step) => '${step.movement.name}:${step.prop.protocolValue}')
          .toList();

      expect(variants, const [
        'Hand Stall:bottle',
        'Hand Stall:shaker',
        'Forearm Stall:bottle',
        'Forearm Stall:shaker',
        'Elbow Stall:bottle',
        'Elbow Stall:shaker',
        'Wrist Stall:bottle',
        'Wrist Stall:shaker',
        'One Finger Stall:bottle',
        'One Finger Stall:shaker',
      ]);
    });

    test('Bottle and Shaker aggregates remain independent', () {
      final sessions = [
        session(prop: TrainingProp.bottle, rubricTotal: 8),
        session(prop: TrainingProp.bottle, rubricTotal: 12),
        session(prop: TrainingProp.bottle),
        session(prop: TrainingProp.shaker, rubricTotal: 6),
      ];

      final variantStats = aggregatePracticeVariantStats(sessions);
      final bottle =
          variantStats[practiceVariantKey('Hand Stall', TrainingProp.bottle)]!;
      final shaker =
          variantStats[practiceVariantKey('Hand Stall', TrainingProp.shaker)]!;

      expect(bottle.count, 3);
      expect(bottle.rubricSessionCount, 2);
      expect(bottle.averageRubricTotal, 10);
      expect(shaker.count, 1);
      expect(shaker.rubricSessionCount, 1);
      expect(shaker.averageRubricTotal, 6);

      final movementStats = aggregateMovementStats(sessions);
      expect(movementStats['Hand Stall']!.count, 4);
      expect(
        movementStats['Hand Stall']!.averageRubricTotal,
        closeTo(26 / 3, 0.001),
      );
    });
  });

  group('MovementCard', () {
    testWidgets('separate cards visibly and semantically identify each prop', (
      tester,
    ) async {
      final handStall = movementNamed('Hand Stall');
      await tester.pumpWidget(
        wrapWithProgression(
          Row(
            children: [
              movementCard(movement: handStall, prop: TrainingProp.bottle),
              movementCard(movement: handStall, prop: TrainingProp.shaker),
            ],
          ),
          level: 20,
          tutorialsCompleted: true,
        ),
      );

      expect(find.text('Hand Stall'), findsNWidgets(2));
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Cocktail Shaker'), findsOneWidget);
      expect(find.text('Practice with'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Hand Stall. Bottle. Medium. New. Ready to learn. Start practice',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Hand Stall. Cocktail Shaker. Medium. New. Ready to learn. Start practice',
        ),
        findsOneWidget,
      );

      final images = tester.widgetList<MovementImage>(
        find.byType(MovementImage),
      );
      expect(images.map((image) => image.prop), [
        TrainingProp.bottle,
        TrainingProp.shaker,
      ]);
      expect(
        MovementVisuals.assetPathFor('Hand Stall', prop: TrainingProp.shaker),
        'assets/movements_icon/shaker_hand_stall.png',
      );
    });

    testWidgets('Bottle and Shaker cards navigate with only their exact prop', (
      tester,
    ) async {
      final handStall = movementNamed('Hand Stall');

      Future<void> open(TrainingProp prop) async {
        final navigated = <String>[];
        final router = trackingRouter(
          home: ScaffoldPage(
            content: movementCard(movement: handStall, prop: prop),
          ),
          navigatedLocations: navigated,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          withProgression(
            routerApp(router),
            level: 20,
            tutorialsCompleted: true,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(MovementCard));
        await tester.pumpAndSettle();

        expect(navigated, hasLength(1));
        expect(navigated.single, contains('movement=Hand%20Stall'));
        expect(navigated.single, contains('difficulty=Medium'));
        expect(navigated.single, contains('prop=${prop.protocolValue}'));
      }

      await open(TrainingProp.bottle);
      await open(TrainingProp.shaker);
    });

    testWidgets('a later locked prop is identifiable but cannot navigate', (
      tester,
    ) async {
      final navigated = <String>[];
      final router = trackingRouter(
        home: ScaffoldPage(
          content: movementCard(
            movement: movementNamed('Hand Stall'),
            prop: TrainingProp.shaker,
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(withProgression(routerApp(router), level: 6));
      await tester.pumpAndSettle();

      expect(find.text('Hand Stall'), findsOneWidget);
      expect(find.text('Cocktail Shaker'), findsOneWidget);
      expect(find.text('Locked · Level 7'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Hand Stall. Cocktail Shaker. Medium. New. Ready to learn. Locked · Level 7',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byType(MovementCard));
      await tester.pumpAndSettle();
      expect(navigated, isEmpty);
    });

    testWidgets('movement identity remains hidden before earliest reveal', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithProgression(
          movementCard(
            movement: movementNamed('Hand Stall'),
            prop: TrainingProp.shaker,
          ),
          level: 5,
        ),
      );

      expect(find.text('Hand Stall'), findsNothing);
      expect(find.text('Cocktail Shaker'), findsNothing);
      expect(find.text('???'), findsOneWidget);
      expect(find.text('Unlocks at Level 6'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Mystery movement. Locked. Unlocks at Level 6.'),
        findsOneWidget,
      );
    });

    testWidgets('Bottle in a tin keeps its combined prop and route', (
      tester,
    ) async {
      final navigated = <String>[];
      final router = trackingRouter(
        home: ScaffoldPage(
          content: movementCard(
            movement: movementNamed('Bottle in a tin'),
            prop: TrainingProp.bottleAndShaker,
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        withProgression(routerApp(router), level: 20, tutorialsCompleted: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bottle + Cocktail Shaker'), findsOneWidget);
      final image = tester.widget<MovementImage>(find.byType(MovementImage));
      expect(image.prop, TrainingProp.bottleAndShaker);

      await tester.tap(find.byType(MovementCard));
      await tester.pumpAndSettle();
      expect(navigated.single, contains('prop=bottle_and_shaker'));
    });

    testWidgets('hover and keyboard focus retain interaction and navigation', (
      tester,
    ) async {
      final navigated = <String>[];
      final router = trackingRouter(
        home: ScaffoldPage(
          content: movementCard(
            movement: movementNamed('Hand Stall'),
            prop: TrainingProp.bottle,
            sessionCount: 2,
            averageRubricTotal: 9,
          ),
        ),
        navigatedLocations: navigated,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        withProgression(routerApp(router), level: 20, tutorialsCompleted: true),
      );
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(MovementCard)));
      await tester.pumpAndSettle();
      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.text('Average rubric 9 / 12'), findsOneWidget);
      await mouse.removePointer();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(navigated, hasLength(1));
      expect(navigated.single, contains('prop=bottle'));
    });

    testWidgets('high contrast and reduced motion render without overflow', (
      tester,
    ) async {
      await setSurface(tester, const Size(360, 700));
      await tester.pumpWidget(
        wrapWithProgression(
          movementCard(
            movement: movementNamed('Hand Stall'),
            prop: TrainingProp.shaker,
          ),
          level: 20,
          tutorialsCompleted: true,
          highContrast: true,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cocktail Shaker'), findsOneWidget);
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('movement-card-surface')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(surface.duration, Duration.zero);
      expect(surface.transform!.storage[13], 0);
      expect(decoration.gradient, isNull);
      expect(decoration.boxShadow, isEmpty);
      expect(decoration.border!.top.width, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('variant cards remain readable in light and dark themes', (
      tester,
    ) async {
      for (final brightness in const [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          withProgression(
            wrap(
              movementCard(
                movement: movementNamed('Hand Stall'),
                prop: TrainingProp.shaker,
                sessionCount: 2,
                averageRubricTotal: 9,
              ),
              brightness: brightness,
            ),
            level: 20,
            tutorialsCompleted: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cocktail Shaker'), findsOneWidget);
        expect(find.text('Average rubric 9 / 12'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('MovementDifficultySection', () {
    testWidgets('Medium renders 10 separate prop-specific cards in order', (
      tester,
    ) async {
      await setSurface(tester, const Size(1500, 1200));
      final steps = practiceStepsForDifficulty('Medium');
      await tester.pumpWidget(
        wrapWithProgression(
          SizedBox(
            width: 1280,
            child: MovementDifficultySection(
              difficulty: 'Medium',
              practiceSteps: steps,
              stats: const {},
            ),
          ),
          level: 20,
          tutorialsCompleted: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MovementCard), findsNWidgets(10));
      expect(find.text('Hand Stall'), findsNWidgets(2));
      expect(find.text('Bottle'), findsNWidgets(5));
      expect(find.text('Cocktail Shaker'), findsNWidgets(5));

      final images = tester
          .widgetList<MovementImage>(find.byType(MovementImage))
          .map((image) => '${image.movementName}:${image.prop!.protocolValue}')
          .toList();
      expect(images, const [
        'Hand Stall:bottle',
        'Hand Stall:shaker',
        'Forearm Stall:bottle',
        'Forearm Stall:shaker',
        'Elbow Stall:bottle',
        'Elbow Stall:shaker',
        'Wrist Stall:bottle',
        'Wrist Stall:shaker',
        'One Finger Stall:bottle',
        'One Finger Stall:shaker',
      ]);

      final cards = find.byType(MovementCard);
      for (var index = 1; index < 5; index++) {
        expect(
          tester.getTopLeft(cards.at(index)).dy,
          closeTo(tester.getTopLeft(cards.first).dy, 1),
        );
      }
      expect(
        tester.getTopLeft(cards.at(5)).dy,
        greaterThan(tester.getTopLeft(cards.first).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('practice count and card stats use exact variants', (
      tester,
    ) async {
      final steps = practiceStepsForDifficulty('Medium').take(2).toList();
      final bottleKey = practiceVariantKey('Hand Stall', TrainingProp.bottle);
      await tester.pumpWidget(
        wrapWithProgression(
          SizedBox(
            width: 700,
            child: MovementDifficultySection(
              difficulty: 'Medium',
              practiceSteps: steps,
              stats: {
                bottleKey: const (
                  count: 3,
                  rubricSessionCount: 2,
                  averageRubricTotal: 10,
                ),
              },
            ),
          ),
          level: 20,
          tutorialsCompleted: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 practiced'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Practiced'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('3 sessions'), findsOneWidget);
      expect(find.text('Average rubric 10 / 12'), findsOneWidget);
    });

    testWidgets('wide and narrow variant grids do not overflow', (
      tester,
    ) async {
      final steps = practiceStepsForDifficulty('Medium');
      for (final size in const [Size(1500, 1200), Size(560, 5200)]) {
        await setSurface(tester, size);
        await tester.pumpWidget(
          wrapWithProgression(
            SizedBox(
              width: size.width == 1500 ? 1280 : 520,
              child: MovementDifficultySection(
                difficulty: 'Medium',
                practiceSteps: steps,
                stats: const {},
              ),
            ),
            level: 20,
            tutorialsCompleted: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MovementCard), findsNWidgets(10));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('section remains collapsible with reduced motion', (
      tester,
    ) async {
      await setSurface(tester, const Size(1000, 1200));
      await tester.pumpWidget(
        wrapWithProgression(
          SizedBox(
            width: 900,
            child: MovementDifficultySection(
              difficulty: 'Easy',
              practiceSteps: practiceStepsForDifficulty('Easy'),
              stats: const {},
            ),
          ),
          level: 20,
          tutorialsCompleted: true,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      final transition = find.descendant(
        of: find.byType(MovementDifficultySection),
        matching: find.byType(SizeTransition),
      );
      await tester.tap(find.text('Easy — Foundations'));
      await tester.pump();
      expect(tester.getSize(transition).height, lessThan(1));
    });
  });

  testWidgets('header preserves the 20-variant total', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MovementsHeader(
          summary: MovementsSummary(
            practicedCount: 3,
            totalMovements: 20,
            totalSessions: 4,
            rubricSessionCount: 3,
            overallAverageRubric: 9,
          ),
        ),
      ),
    );

    expect(find.text('3 of 20'), findsOneWidget);
    expect(find.text('9.0 / 12'), findsOneWidget);
  });
}
