import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/features/movements/movements_presentation.dart';
import 'package:elixr_application/features/movements/widgets/movement_card.dart';
import 'package:elixr_application/features/movements/widgets/movement_difficulty_section.dart';
import 'package:elixr_application/features/movements/widgets/movements_header.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return FluentApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: ScaffoldPage(content: child),
  );
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

const easyMovement = Movement(
  name: 'Normal Grip',
  difficulty: 'Easy',
  description: 'Hold the bottle with a standard overhand grip.',
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
      expect(find.text('3 of 9 practiced'), findsOneWidget);
      expect(find.text('6 sessions completed'), findsOneWidget);
      expect(find.text('84% overall average'), findsOneWidget);
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
      expect(find.text('0 sessions completed'), findsOneWidget);
    });
  });

  group('MovementCard', () {
    testWidgets('shows start state for unpracticed movement', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 360,
            height: 248,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 0,
              avgScore: 0,
            ),
          ),
        ),
      );

      expect(find.text('Not practiced yet'), findsOneWidget);
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
            width: 360,
            height: 248,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              avgScore: 84.4,
            ),
          ),
        ),
      );

      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.text('Average score 84%'), findsOneWidget);
      expect(find.text('Practice again'), findsOneWidget);
      expect(find.textContaining('Best avg'), findsNothing);
    });

    testWidgets('practiced card fits a fixed grid cell without overflow', (
      tester,
    ) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await setSurface(tester, const Size(400, 300));
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 360,
            height: 248,
            child: MovementCard(
              movement: easyMovement,
              sessionCount: 2,
              avgScore: 100,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Practice again'), findsOneWidget);
      expect(errors.where((e) => e.toString().contains('OVERFLOWED')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows locked state without activation affordance text', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 360,
            height: 248,
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
  });

  group('MovementDifficultySection', () {
    testWidgets('renders section title and responsive grid columns', (
      tester,
    ) async {
      const second = Movement(
        name: "Bartender's Grip",
        difficulty: 'Easy',
        description: 'Pinch the neck with thumb and index finger.',
        requiresHandsDetection: true,
        enabled: true,
      );
      const third = Movement(
        name: 'Reverse Grip',
        difficulty: 'Easy',
        description: 'Hold the bottle with an underhand grip.',
        requiresHandsDetection: true,
        enabled: true,
      );

      await setSurface(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrap(
          const MovementDifficultySection(
            difficulty: 'Easy',
            movements: [easyMovement, second, third],
            stats: {'Normal Grip': (count: 1, avgScore: 70)},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Easy — Foundations'), findsOneWidget);
      expect(find.text('1 of 3 practiced'), findsOneWidget);
      expect(find.byType(MovementCard), findsNWidgets(3));
    });

    testWidgets('uses a single column on narrow widths', (tester) async {
      await setSurface(tester, const Size(600, 900));
      await tester.pumpWidget(
        wrap(
          MovementDifficultySection(
            difficulty: 'Medium',
            movements: const [easyMovement, easyMovement],
            stats: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medium — Balance and control'), findsOneWidget);
      final cards = tester.widgetList<MovementCard>(find.byType(MovementCard));
      expect(cards.length, 2);
      final first = tester.getTopLeft(find.byType(MovementCard).at(0));
      final second = tester.getTopLeft(find.byType(MovementCard).at(1));
      expect(second.dy, greaterThan(first.dy));
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
                width: 360,
                height: 248,
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

      expect(find.text('75% overall average'), findsOneWidget);
      expect(find.text('Average score 75%'), findsOneWidget);
    });
  });
}
