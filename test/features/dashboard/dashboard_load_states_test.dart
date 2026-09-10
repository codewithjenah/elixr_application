import 'dart:async';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/daily_quest_board.dart';
import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/gamification_repository.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/session_repository.dart';
import 'package:elixr_application/features/dashboard/dashboard_screen.dart';
import 'package:elixr_application/features/teacher/activity_center/activity_read_store.dart';
import 'package:elixr_application/features/trainee/activity_center/trainee_activity_controller.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/in_memory_classroom_announcement_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:firebase_core/firebase_core.dart';
// Test-only Firebase bootstrap; not part of app dependencies.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

User _user(String id, String firstName) {
  return User(
    id: id,
    firstName: firstName,
    lastName: 'Trainee',
    email: '$id@example.test',
  );
}

Session _session({
  String userId = 'user-a',
  String movementName = 'Normal Grip',
}) {
  return Session(
    userId: userId,
    movementName: movementName,
    difficulty: 'Easy',
    rubric: const RubricAssessment(
      technique: 3,
      stability: 2,
      completion: 2,
      propPositioning: 2,
    ),
    assessmentVersion: 2,
    durationSeconds: 60,
    createdAt: '2026-09-10T04:00:00.000Z',
    propType: TrainingProp.bottle,
  );
}

List<Session> _nSessions(int count, {String userId = 'user-a'}) {
  return [for (var i = 0; i < count; i++) _session(userId: userId)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('first-load failure shows dashboard unavailable with Retry', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      user: _user('user-a', 'Ada'),
      sessions: _FakeSessionRepository(_nSessions(7))
        ..error = StateError('unavailable'),
    );

    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Total Sessions'), findsNothing);
  });

  testWidgets(
    'transient refresh failure keeps previous values and shows Retry',
    (tester) async {
      final sessions = _FakeSessionRepository(_nSessions(7));
      final sessionService = SessionService(
        repository: sessions,
        recordCompletedSessionOverride:
            ({
              required sessionId,
              required userId,
              required displayName,
              profilePictureUrl,
            }) async {},
      );
      addTearDown(sessionService.dispose);

      await _pumpDashboard(
        tester,
        user: _user('user-a', 'Ada'),
        sessions: sessions,
        sessionService: sessionService,
      );

      expect(find.text('Total Sessions'), findsOneWidget);
      expect(find.textContaining('7 session'), findsOneWidget);
      expect(find.text('Dashboard unavailable'), findsNothing);

      sessions.error = StateError('unavailable');
      sessionService.notifyListeners();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('7 session'), findsOneWidget);
      expect(
        find.text('We could not load your dashboard. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Dashboard unavailable'), findsNothing);

      sessions.error = null;
      sessions.sessions = _nSessions(11);
      final retry = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Retry'),
      );
      retry.onPressed!();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('11 session'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('user switch does not keep the previous user dashboard', (
    tester,
  ) async {
    final sessions = _FakeSessionRepository(_nSessions(7));
    final auth = AuthService(
      repository: _StubAuthRepository(),
      leaderboardRepository: null,
    )..seedAuthenticatedUser(_user('user-a', 'Ada'));
    addTearDown(auth.dispose);

    await _pumpDashboard(
      tester,
      user: _user('user-a', 'Ada'),
      sessions: sessions,
      auth: auth,
    );
    expect(find.textContaining('7 session'), findsOneWidget);

    final blocked = Completer<List<Session>>();
    sessions.completer = blocked;
    sessions.sessions = _nSessions(3, userId: 'user-b');
    auth.seedAuthenticatedUser(_user('user-b', 'Bea'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading your dashboard'), findsOneWidget);
    expect(find.text('Total Sessions'), findsNothing);

    blocked.complete(sessions.sessions);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('3 session'), findsOneWidget);
    expect(find.textContaining('7 session'), findsNothing);
  });

  testWidgets('late previous-user load cannot overwrite the current user', (
    tester,
  ) async {
    final sessions = _FakeSessionRepository(_nSessions(7));
    final auth = AuthService(
      repository: _StubAuthRepository(),
      leaderboardRepository: null,
    )..seedAuthenticatedUser(_user('user-a', 'Ada'));
    addTearDown(auth.dispose);

    final firstSessions = Completer<List<Session>>();
    sessions.completer = firstSessions;

    await _pumpDashboard(
      tester,
      user: _user('user-a', 'Ada'),
      sessions: sessions,
      auth: auth,
    );

    sessions.completer = null;
    sessions.sessions = _nSessions(3, userId: 'user-b');
    auth.seedAuthenticatedUser(_user('user-b', 'Bea'));
    await tester.pump();
    await tester.pump();

    firstSessions.complete(_nSessions(99));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('3 session'), findsOneWidget);
    expect(find.textContaining('99 session'), findsNothing);
    expect(find.textContaining('7 session'), findsNothing);
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required User user,
  required _FakeSessionRepository sessions,
  AuthService? auth,
  SessionService? sessionService,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authService =
      auth ??
      (AuthService(
        repository: _StubAuthRepository(),
        leaderboardRepository: null,
      )..seedAuthenticatedUser(user));
  if (auth == null) {
    addTearDown(authService.dispose);
  }

  final ownedSessionService =
      sessionService ??
      SessionService(
        repository: sessions,
        recordCompletedSessionOverride:
            ({
              required sessionId,
              required userId,
              required displayName,
              profilePictureUrl,
            }) async {},
      );
  if (sessionService == null) {
    addTearDown(ownedSessionService.dispose);
  }

  final gamification = _FakeGamificationRepository();
  addTearDown(gamification.dispose);
  final activity = TraineeActivityController(
    groupRepository: InMemoryGroupRepository(),
    assignmentRepository: InMemoryClassroomAssignmentRepository(),
    announcementRepository: InMemoryClassroomAnnouncementRepository(),
    readStore: InMemoryActivityReadStore(),
    periodicTimer: (duration, onTick) {
      final timer = Timer(duration, () {});
      timer.cancel();
      return timer;
    },
  );
  addTearDown(activity.dispose);

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => DashboardScreen(
          sessionRepository: sessions,
          leaderboardRepository: _FakeLeaderboardRepository(),
          gamificationRepository: gamification,
        ),
      ),
      GoRoute(
        path: '/movements',
        builder: (context, state) =>
            const ScaffoldPage(content: Text('Movements')),
      ),
      GoRoute(
        path: '/leaderboard',
        builder: (context, state) =>
            const ScaffoldPage(content: Text('Leaderboard')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<SessionService>.value(
          value: ownedSessionService,
        ),
        ChangeNotifierProvider<TraineeProgressionService>(
          create: (_) => TraineeProgressionService.ready(totalXp: 20 * 250),
        ),
        ChangeNotifierProvider<TutorialProgressService>(
          create: (_) => _ReadyTutorials(),
        ),
        ChangeNotifierProvider<TraineeActivityController>.value(
          value: activity,
        ),
      ],
      child: FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _ReadyTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;

  @override
  bool hasCompletedLesson(String movement, TrainingProp prop) => true;
}

class _FakeSessionRepository extends SessionRepository {
  _FakeSessionRepository(this.sessions);

  List<Session> sessions;
  Object? error;
  Completer<List<Session>>? completer;

  @override
  Future<List<Session>> getSessionsForUser(String userId) async {
    if (completer != null) return completer!.future;
    if (error != null) throw error!;
    return sessions;
  }
}

class _FakeLeaderboardRepository extends LeaderboardRepository {
  @override
  Stream<List<LeaderboardEntry>> watchTopPlayers({
    int limit = 10,
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    DateTime? nowUtc,
  }) {
    return Stream.value(const []);
  }

  @override
  Future<LeaderboardSyncResult> syncCurrentUserLeaderboard({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    return LeaderboardSyncResult.empty;
  }
}

class _FakeGamificationRepository extends GamificationRepository {
  _FakeGamificationRepository()
    : _board = DailyQuestBoard(
        userId: 'user-a',
        dayKey: '20260910',
        dayStart: DateTime.utc(2026, 9, 9, 16),
        questIds: const [
          'session_count_1',
          'duration_20min',
          'score_95',
          'practice_easy_movement',
          'sessions_above_70_x2',
        ],
      );

  final DailyQuestBoard _board;
  final _claimedController = StreamController<Set<String>>.broadcast();

  void dispose() {
    _claimedController.close();
  }

  @override
  Future<DailyQuestBoard> getOrCreateDailyBoard({
    required String userId,
    required int currentLevel,
    DateTime? nowUtc,
  }) async {
    return _board;
  }

  @override
  Stream<Set<String>> watchClaimedQuestIds({
    required String userId,
    required String boardId,
  }) async* {
    yield const <String>{};
    yield* _claimedController.stream;
  }
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
