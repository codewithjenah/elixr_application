import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/calendar/utils/calendar_metrics.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_calendar_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

Future<void> _setSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('View Planner navigates to Training planner', (tester) async {
    await _setSurface(tester);
    final navigated = <String>[];
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => ScaffoldPage(
            content: DashboardCalendarCard(
              practicedDays: {normalizeDate(DateTime.now())},
              onViewCalendar: () => context.go('/training?view=planner'),
              onDateSelected: (_) {},
            ),
          ),
        ),
        GoRoute(
          path: '/training',
          builder: (context, state) {
            navigated.add(state.uri.toString());
            return const ScaffoldPage(content: Center(child: Text('Training')));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Planner'));
    await tester.pumpAndSettle();
    expect(navigated, ['/training?view=planner']);
  });

  testWidgets('practiced date navigates with zero-padded YYYY-MM-DD', (
    tester,
  ) async {
    await _setSurface(tester);
    final navigated = <String>[];
    final now = DateTime.now();
    final practiced = DateTime(now.year, now.month, 1);
    final expected =
        '${practiced.year.toString().padLeft(4, '0')}-'
        '${practiced.month.toString().padLeft(2, '0')}-'
        '${practiced.day.toString().padLeft(2, '0')}';
    expect(expected, DateFormat('yyyy-MM-dd').format(practiced));

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => ScaffoldPage(
            content: DashboardCalendarCard(
              practicedDays: {practiced},
              onViewCalendar: () {},
              onDateSelected: (date) {
                final value = DateFormat('yyyy-MM-dd').format(date);
                context.go('/training?view=planner&date=$value');
              },
            ),
          ),
        ),
        GoRoute(
          path: '/training',
          builder: (context, state) {
            navigated.add(state.uri.toString());
            return const ScaffoldPage(content: Center(child: Text('Training')));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(navigated, ['/training?view=planner&date=$expected']);
    expect(expected.split('-')[1].length, 2);
    expect(expected.split('-')[2].length, 2);
  });

  test('Dashboard and Calendar share streak and date utilities', () {
    final sessions = [
      Session(
        userId: 'u1',
        movementName: 'Flair',
        difficulty: 'Easy',
        legacyScore: 80,
        durationSeconds: 60,
        createdAt: '2026-08-01T10:00:00.000',
      ),
      Session(
        userId: 'u1',
        movementName: 'Flair',
        difficulty: 'Easy',
        legacyScore: 90,
        durationSeconds: 60,
        createdAt: '2026-08-02T10:00:00.000',
      ),
    ];

    final dates = practicedDates(sessions);
    expect(dates, {DateTime(2026, 8, 1), DateTime(2026, 8, 2)});
    expect(currentStreak(dates, referenceDate: DateTime(2026, 8, 2)), 2);
    expect(monthGridDates(2026, 8).first.weekday, DateTime.monday);
  });
}
