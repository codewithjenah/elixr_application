import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/locked_movement_mark.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/features/learning/learning_center_screen.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _IncompleteTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;
}

Widget _wrapLearning(Widget child, {required int level}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TraineeProgressionService>(
        create: (_) => TraineeProgressionService.ready(
          totalXp: (level - 1) * GamificationRules.xpPerLevel,
        ),
      ),
      ChangeNotifierProvider<TutorialProgressService>(
        create: (_) => _IncompleteTutorials(),
      ),
    ],
    child: child,
  );
}

void main() {
  testWidgets('learning center renders at desktop and compact widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in const [Size(1440, 900), Size(560, 900)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        FluentApp(theme: AppTheme.dark, home: const LearningCenterScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Help & Tutorials'), findsOneWidget);
      expect(find.text('Start with the essentials'), findsOneWidget);
      expect(find.text('How your performance is measured'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'below required level, future cards are generic and not navigable',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);

      final router = GoRouter(
        initialLocation: '/learn',
        routes: [
          GoRoute(
            path: '/learn',
            builder: (_, _) => const LearningCenterScreen(),
          ),
          GoRoute(
            path: '/learn/movement/:name',
            builder: (context, state) =>
                Text('Opened ${state.pathParameters['name']}'),
          ),
        ],
      );

      await tester.pumpWidget(
        _wrapLearning(
          FluentApp.router(theme: AppTheme.dark, routerConfig: router),
          level: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Normal Grip'), findsOneWidget);
      expect(find.text('Hand Stall'), findsNothing);
      expect(find.text('Balance the bottle on your open palm.'), findsNothing);
      expect(find.bySemanticsLabel('Movement image: Hand Stall'), findsNothing);
      expect(find.text('Locked Movement'), findsWidgets);
      expect(find.text('Unlocks at Level 5'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Locked movement, unlocks at Level 5'),
        findsOneWidget,
      );

      final unlockFinder = find.text('Unlocks at Level 5');
      await tester.ensureVisible(unlockFinder);
      await tester.pumpAndSettle();
      await tester.tap(unlockFinder);
      await tester.pumpAndSettle();
      expect(find.textContaining('Opened'), findsNothing);
      expect(find.text('Help & Tutorials'), findsOneWidget);
    },
  );

  testWidgets(
    'exact unlock level reveals the movement while later props stay gated',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);

      await tester.pumpWidget(
        _wrapLearning(
          FluentApp(theme: AppTheme.dark, home: const LearningCenterScreen()),
          level: 5,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hand Stall'), findsOneWidget);
      expect(find.text('Locked Movement'), findsWidgets);
      expect(find.text('Learn'), findsWidgets);
      expect(find.text('Cocktail Shaker · Locked · Level 6'), findsOneWidget);
      expect(find.text('One Finger Stall'), findsNothing);
    },
  );

  testWidgets('loading state is spoiler-safe at desktop and compact widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in const [Size(1440, 900), Size(560, 900)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TraineeProgressionService>(
              create: (_) => TraineeProgressionService(),
            ),
            ChangeNotifierProvider<TutorialProgressService>(
              create: (_) => _IncompleteTutorials(),
            ),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const LearningCenterScreen(),
          ),
        ),
      );
      await tester.pump();

      for (final movement in movementCatalog.where((m) => m.enabled)) {
        expect(find.text(movement.name), findsNothing);
        expect(
          find.bySemanticsLabel('Movement image: ${movement.name}'),
          findsNothing,
        );
      }
      expect(find.byType(MovementImage), findsNothing);
      expect(find.byType(LockedMovementMark), findsNothing);
      expect(find.text('Help & Tutorials'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
