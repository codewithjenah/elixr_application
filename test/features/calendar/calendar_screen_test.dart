import 'dart:async';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/features/calendar/calendar_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Feedback;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

const _userId = 'calendar-user';

/// Assessment V2 fixture; distributes a 0..12 total across the four criteria.
Session _session({
  required String createdAt,
  int rubricTotal = 8,
  int durationSeconds = 60,
  String difficulty = 'Easy',
  String movementName = 'Hand Stall',
}) {
  final scores = <int>[0, 0, 0, 0];
  var remaining = rubricTotal.clamp(0, 12);
  for (var i = 0; i < scores.length && remaining > 0; i++) {
    final value = remaining >= 3 ? 3 : remaining;
    scores[i] = value;
    remaining -= value;
  }

  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    rubric: RubricAssessment(
      technique: scores[0],
      stability: scores[1],
      completion: scores[2],
      propPositioning: scores[3],
    ),
    assessmentVersion: 2,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
  );
}

class _StubAuthRepository implements AuthRepositoryBase {
  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> deleteAccount({required String password}) async {}

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }
}

Future<void> _setSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService authService;
  late SessionService sessionService;

  setUp(() {
    authService =
        AuthService(
          repository: _StubAuthRepository(),
          leaderboardRepository: null,
        )..seedAuthenticatedUser(
          const User(
            id: _userId,
            firstName: 'Cal',
            lastName: 'Trainer',
            email: 'cal@example.com',
          ),
        );
    sessionService = SessionService(
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {},
      recordCompletedSessionOverride:
          ({
            required sessionId,
            required userId,
            required displayName,
            profilePictureUrl,
          }) async {},
    );
  });

  tearDown(() {
    authService.dispose();
    sessionService.dispose();
  });

  Future<void> pumpCalendar(
    WidgetTester tester, {
    String? initialDate,
    CalendarSessionsLoader? sessionsLoader,
    List<String>? navigated,
  }) async {
    await _setSurface(tester);
    final locations = navigated ?? <String>[];
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (context, state) => CalendarScreen(
            initialDate: initialDate,
            sessionsLoader: sessionsLoader,
          ),
        ),
        GoRoute(
          path: '/movements',
          builder: (context, state) {
            locations.add('/movements');
            return const ScaffoldPage(
              content: Center(child: Text('Movements')),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<SessionService>.value(value: sessionService),
        ],
        child: FluentApp.router(
          theme: AppTheme.dark,
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          routeInformationProvider: router.routeInformationProvider,
        ),
      ),
    );
  }

  testWidgets('shows loading indicator while sessions load', (tester) async {
    final completer = Completer<List<Session>>();
    await pumpCalendar(tester, sessionsLoader: (_) => completer.future);
    await tester.pump();
    expect(find.byType(ProgressRing), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(ProgressRing), findsNothing);
  });

  testWidgets('shows title, subtitle, and current month', (tester) async {
    await pumpCalendar(tester, sessionsLoader: (_) async => const []);
    await tester.pumpAndSettle();

    expect(find.text('Training Calendar'), findsOneWidget);
    expect(
      find.text('Review your consistency and daily practice activity'),
      findsOneWidget,
    );
    expect(
      find.text(DateFormat.yMMMM().format(DateTime.now())),
      findsOneWidget,
    );
  });

  testWidgets('empty calendar still shows grid and empty selected day', (
    tester,
  ) async {
    await pumpCalendar(tester, sessionsLoader: (_) async => const []);
    await tester.pumpAndSettle();

    expect(find.text('Active Days'), findsOneWidget);
    expect(find.text('No practice recorded'), findsOneWidget);
    expect(find.text('Start Practice'), findsOneWidget);
    expect(find.text('MON'), findsOneWidget);
  });

  testWidgets('summary cards show monthly activity and streak', (tester) async {
    final today = DateTime.now();
    final stamp =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}T12:00:00.000';

    await pumpCalendar(
      tester,
      sessionsLoader: (_) async => [
        _session(createdAt: stamp, rubricTotal: 11),
        _session(createdAt: stamp, rubricTotal: 7),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Monthly Sessions'), findsOneWidget);
    // Two sessions on one day => 1 active day, 2 monthly sessions, streak 1.
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('selecting an active date shows its sessions', (tester) async {
    await pumpCalendar(
      tester,
      initialDate: '2026-08-01',
      sessionsLoader: (_) async => [
        _session(
          createdAt: '2026-08-01T10:00:00.000',
          movementName: 'Flair',
          rubricTotal: 10,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Flair'), findsOneWidget);
    expect(find.text('No practice recorded'), findsNothing);
    expect(find.text('10 / 12'), findsWidgets);
    expect(find.text('Proficient'), findsOneWidget);
    expect(find.text('Average Rubric'), findsOneWidget);
  });

  testWidgets('selecting an empty date shows empty state', (tester) async {
    await pumpCalendar(
      tester,
      initialDate: '2026-08-15',
      sessionsLoader: (_) async => [
        _session(createdAt: '2026-08-01T10:00:00.000'),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('No practice recorded'), findsOneWidget);
  });

  testWidgets('previous and next month navigation update the label', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      initialDate: '2026-08-15',
      sessionsLoader: (_) async => const [],
    );
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('Today button returns to the current month', (tester) async {
    final now = DateTime.now();
    await pumpCalendar(
      tester,
      initialDate: '2025-01-15',
      sessionsLoader: (_) async => const [],
    );
    await tester.pumpAndSettle();

    expect(find.text('January 2025'), findsOneWidget);
    await tester.tap(find.widgetWithText(Button, 'Today'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat.yMMMM().format(now)), findsOneWidget);
  });

  testWidgets('valid initialDate opens that month and date', (tester) async {
    await pumpCalendar(
      tester,
      initialDate: '2026-07-04',
      sessionsLoader: (_) async => [
        _session(
          createdAt: '2026-07-04T09:00:00.000',
          movementName: 'Shoulder Stall',
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('Shoulder Stall'), findsOneWidget);
  });

  testWidgets('invalid initialDate falls back to today safely', (tester) async {
    await pumpCalendar(
      tester,
      initialDate: 'not-a-date',
      sessionsLoader: (_) async => const [],
    );
    await tester.pumpAndSettle();

    expect(find.text('Training Calendar'), findsOneWidget);
    expect(
      find.text(DateFormat.yMMMM().format(DateTime.now())),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start Practice navigates to movements', (tester) async {
    final navigated = <String>[];
    await pumpCalendar(
      tester,
      sessionsLoader: (_) async => const [],
      navigated: navigated,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Practice'));
    await tester.pumpAndSettle();
    expect(navigated, ['/movements']);
  });
}
