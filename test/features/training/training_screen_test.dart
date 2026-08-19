import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/training/training_screen.dart';
import 'package:elixr_application/features/training/training_view.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _setSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

GoRouter _trainingRouter({String initialLocation = '/training'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/training',
        builder: (context, state) {
          return TrainingScreen(
            view: TrainingView.fromQuery(
              state.uri.queryParameters[TrainingView.viewQueryParameter],
            ),
            date: state.uri.queryParameters[TrainingView.dateQueryParameter],
            planner: const Center(child: Text('Planner pane')),
            history: const Center(child: Text('History pane')),
          );
        },
      ),
      GoRoute(
        path: '/calendar',
        redirect: (context, state) => trainingLocationFromCalendar(
          date: state.uri.queryParameters[TrainingView.dateQueryParameter],
        ),
      ),
      GoRoute(
        path: '/history',
        redirect: (context, state) => trainingLocationFromHistory(
          date: state.uri.queryParameters[TrainingView.dateQueryParameter],
        ),
      ),
    ],
  );
}

Future<GoRouter> _pumpTraining(
  WidgetTester tester, {
  required String location,
}) async {
  await _setSurface(tester);
  final router = _trainingRouter(initialLocation: location);
  await tester.pumpWidget(
    FluentApp.router(
      theme: AppTheme.dark,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      routeInformationProvider: router.routeInformationProvider,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrainingView', () {
    test('defaults missing and invalid view values to planner', () {
      expect(TrainingView.fromQuery(null), TrainingView.planner);
      expect(TrainingView.fromQuery(''), TrainingView.planner);
      expect(TrainingView.fromQuery('planner'), TrainingView.planner);
      expect(TrainingView.fromQuery('history'), TrainingView.history);
      expect(TrainingView.fromQuery('sessions'), TrainingView.planner);
    });

    test('builds deterministic Training locations', () {
      expect(trainingLocation(), '/training?view=planner');
      expect(
        trainingLocation(view: TrainingView.planner),
        '/training?view=planner',
      );
      expect(
        trainingLocation(view: TrainingView.history),
        '/training?view=history',
      );
      expect(
        trainingLocation(view: TrainingView.history, date: '2026-08-19'),
        '/training?view=history&date=2026-08-19',
      );
    });
  });

  group('Training routing', () {
    testWidgets('/training opens Planner', (tester) async {
      await _pumpTraining(tester, location: '/training');
      expect(find.text('Training'), findsWidgets);
      expect(find.text('Planner pane'), findsOneWidget);
      expect(find.text('History pane'), findsNothing);
    });

    testWidgets('/training?view=planner opens Planner', (tester) async {
      await _pumpTraining(tester, location: '/training?view=planner');
      expect(find.text('Planner pane'), findsOneWidget);
      expect(find.text('History pane'), findsNothing);
    });

    testWidgets('/training?view=history opens History', (tester) async {
      await _pumpTraining(tester, location: '/training?view=history');
      expect(find.text('History pane'), findsOneWidget);
      expect(find.text('Planner pane'), findsNothing);
    });

    testWidgets('invalid view falls back to Planner', (tester) async {
      await _pumpTraining(tester, location: '/training?view=nope');
      expect(find.text('Planner pane'), findsOneWidget);
      expect(find.text('History pane'), findsNothing);
    });

    testWidgets('/calendar redirects to Planner', (tester) async {
      final router = await _pumpTraining(tester, location: '/calendar');
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/training?view=planner',
      );
      expect(find.text('Planner pane'), findsOneWidget);
    });

    testWidgets('/calendar?date= preserves the date on Planner', (
      tester,
    ) async {
      final router = await _pumpTraining(
        tester,
        location: '/calendar?date=2026-08-19',
      );
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/training?view=planner&date=2026-08-19',
      );
      expect(find.text('Planner pane'), findsOneWidget);
    });

    testWidgets('/history redirects to History', (tester) async {
      final router = await _pumpTraining(tester, location: '/history');
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/training?view=history',
      );
      expect(find.text('History pane'), findsOneWidget);
    });
  });

  group('Training internal navigation', () {
    testWidgets('clicking History then Planner switches the visible pane', (
      tester,
    ) async {
      final router = await _pumpTraining(tester, location: '/training');
      expect(find.text('Planner pane'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('training-view-history')));
      await tester.pumpAndSettle();
      expect(find.text('History pane'), findsOneWidget);
      expect(find.text('Planner pane'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/training?view=history',
      );

      await tester.tap(find.byKey(const ValueKey('training-view-planner')));
      await tester.pumpAndSettle();
      expect(find.text('Planner pane'), findsOneWidget);
      expect(find.text('History pane'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/training?view=planner',
      );
    });
  });
}
