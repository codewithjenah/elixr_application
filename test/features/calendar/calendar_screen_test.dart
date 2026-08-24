import 'dart:async';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_plan.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/features/calendar/calendar_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Feedback;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

const _userId = 'calendar-user';
final _now = DateTime.utc(2026, 8, 19, 4); // 12:00 Manila on 2026-08-19

Session _session({
  required String createdAt,
  int rubricTotal = 8,
  int durationSeconds = 60,
  String difficulty = 'Medium',
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
    propType: TrainingProp.bottle,
  );
}

TrainingPlan _plan({
  required String dayKey,
  int minutes = 10,
  String movementName = 'Hand Stall',
}) {
  return TrainingPlan.training(
    userId: _userId,
    dayKey: dayKey,
    movementName: movementName,
    difficulty: 'Medium',
    propType: TrainingProp.bottle,
    targetDurationMinutes: minutes,
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
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {}

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

class _PlanStore {
  final plans = <String, TrainingPlan>{};

  Future<List<TrainingPlan>> load(
    String userId, {
    required String startDayKey,
    required String endDayKey,
  }) async {
    return plans.values
        .where(
          (plan) =>
              plan.userId == userId &&
              plan.dayKey.compareTo(startDayKey) >= 0 &&
              plan.dayKey.compareTo(endDayKey) <= 0,
        )
        .toList();
  }

  Future<void> save(TrainingPlan plan) async {
    plans[plan.dayKey] = plan;
  }

  Future<void> remove({required String userId, required String dayKey}) async {
    plans.remove(dayKey);
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
  late _PlanStore planStore;

  setUp(() {
    planStore = _PlanStore();
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
            sessionsLoader: sessionsLoader ?? (_) async => const [],
            plansLoader: planStore.load,
            planSaver: planStore.save,
            planRemover: planStore.remove,
            now: () => _now,
          ),
        ),
        GoRoute(
          path: '/practice',
          builder: (context, state) {
            locations.add(state.uri.toString());
            return const ScaffoldPage(content: Center(child: Text('Practice')));
          },
        ),
        GoRoute(
          path: '/training',
          builder: (context, state) {
            locations.add(state.uri.toString());
            return const ScaffoldPage(content: Center(child: Text('Training')));
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

  testWidgets('shows loading indicator while calendar data loads', (
    tester,
  ) async {
    final completer = Completer<List<Session>>();
    await pumpCalendar(tester, sessionsLoader: (_) => completer.future);
    await tester.pump();
    expect(find.byType(ProgressRing), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(ProgressRing), findsNothing);
  });

  testWidgets('shows the current Manila month without a nested page title', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Training Calendar'), findsNothing);
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('empty calendar still shows grid and unplanned selected day', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Planned Days'), findsOneWidget);
    expect(find.text('No training planned'), findsOneWidget);
    expect(find.text('Plan Practice'), findsOneWidget);
    expect(find.text('Mark Rest Day'), findsOneWidget);
    expect(find.text('MON'), findsOneWidget);
    expect(find.text('No practice recorded'), findsNothing);
  });

  testWidgets(
    'summary cards show adherence metrics instead of session counts',
    (tester) async {
      planStore.plans['20260819'] = _plan(dayKey: '20260819');
      await pumpCalendar(
        tester,
        sessionsLoader: (_) async => [
          _session(createdAt: '2026-08-19T04:00:00.000Z', durationSeconds: 600),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Monthly Sessions'), findsNothing);
      expect(find.text('Adherence'), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);
    },
  );

  testWidgets('selecting a planned day shows the plan, not session rows', (
    tester,
  ) async {
    planStore.plans['20260819'] = _plan(dayKey: '20260819');
    await pumpCalendar(
      tester,
      initialDate: '2026-08-19',
      sessionsLoader: (_) async => [
        _session(
          createdAt: '2026-08-19T04:00:00.000Z',
          durationSeconds: 360,
          rubricTotal: 10,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Training Plan'), findsOneWidget);
    expect(find.text('Hand Stall'), findsWidgets);
    expect(find.text('In Progress'), findsWidgets);
    expect(find.text('Start Practice'), findsOneWidget);
    expect(find.text('Proficient'), findsNothing);
    expect(find.text('Average Rubric'), findsNothing);
  });

  testWidgets('past unplanned days cannot be scheduled retroactively', (
    tester,
  ) async {
    await pumpCalendar(tester, initialDate: '2026-08-15');
    await tester.pumpAndSettle();

    expect(find.text('No training was scheduled.'), findsOneWidget);
    expect(find.text('Plan Practice'), findsNothing);
    expect(find.text('Mark Rest Day'), findsNothing);
  });

  testWidgets('previous and next month navigation update the label', (
    tester,
  ) async {
    await pumpCalendar(tester, initialDate: '2026-08-15');
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('Today button returns to the current Manila month', (
    tester,
  ) async {
    await pumpCalendar(tester, initialDate: '2025-01-15');
    await tester.pumpAndSettle();

    expect(find.text('January 2025'), findsOneWidget);
    await tester.tap(find.widgetWithText(Button, 'Today'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('valid initialDate opens that month and date', (tester) async {
    planStore.plans['20260704'] = _plan(
      dayKey: '20260704',
      movementName: 'Shoulder Stall',
    );
    await pumpCalendar(tester, initialDate: '2026-07-04');
    await tester.pumpAndSettle();

    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('Shoulder Stall'), findsOneWidget);
  });

  testWidgets('invalid initialDate falls back to Manila today safely', (
    tester,
  ) async {
    await pumpCalendar(tester, initialDate: 'not-a-date');
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plan Practice opens the editor and can save a plan', (
    tester,
  ) async {
    await pumpCalendar(tester, initialDate: '2026-08-19');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan Practice'));
    await tester.pumpAndSettle();
    expect(find.text('Save Plan'), findsOneWidget);

    await tester.tap(find.text('Save Plan'));
    await tester.pumpAndSettle();
    expect(planStore.plans.containsKey('20260819'), isTrue);
    expect(find.text('Training Plan'), findsOneWidget);
  });

  testWidgets('Mark Rest Day stores a rest plan', (tester) async {
    await pumpCalendar(tester, initialDate: '2026-08-20');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark Rest Day'));
    await tester.pumpAndSettle();
    expect(planStore.plans['20260820']?.isRest, isTrue);
    expect(find.text('Rest day'), findsOneWidget);
  });

  testWidgets('Start Practice navigates through the existing practice route', (
    tester,
  ) async {
    final navigated = <String>[];
    planStore.plans['20260819'] = _plan(dayKey: '20260819');
    await pumpCalendar(tester, initialDate: '2026-08-19', navigated: navigated);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Practice'));
    await tester.pumpAndSettle();
    expect(
      navigated.single,
      '/practice?movement=Hand+Stall&difficulty=Medium&prop=bottle',
    );
  });

  testWidgets('completed plans offer View History instead of session lists', (
    tester,
  ) async {
    final navigated = <String>[];
    planStore.plans['20260818'] = _plan(dayKey: '20260818');
    await pumpCalendar(
      tester,
      initialDate: '2026-08-18',
      navigated: navigated,
      sessionsLoader: (_) async => [
        _session(createdAt: '2026-08-18T04:00:00.000Z', durationSeconds: 720),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Completed'), findsWidgets);
    expect(find.text('View History'), findsOneWidget);
    await tester.tap(find.text('View History'));
    await tester.pumpAndSettle();
    expect(navigated, ['/training?view=history&date=2026-08-18']);
  });
}
