import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/repositories/progress_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_hero.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_header.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_top_performance.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_training_overview.dart';
import 'package:elixr_application/features/dashboard/widgets/recommended_practice_card.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:elixr_application/features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'package:elixr_application/features/teacher/activity_center/activity_read_store.dart';
import 'package:elixr_application/features/teacher/activity_center/teacher_activity_controller.dart';
import 'package:elixr_application/features/trainee/activity_center/trainee_activity_controller.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_chat_repository.dart';
import 'package:elixr_core/repositories/in_memory_classroom_announcement_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:elixr_core/utils/comparable_rubric_progress.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _SilentAuthRepository
    implements AuthRepositoryBase, TeacherAuthorizationRepositoryBase {
  _SilentAuthRepository([this.user]);
  final User? user;
  @override
  Future<User?> loadPersistedUser() async => user;
  @override
  Future<void> clearCurrentUser() async {}
  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<bool> isCurrentEmailVerified() async => true;
  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}
  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<void> ensureTeacherRoleClaim() async {}

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
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
}

class _TestTraineeActivityController extends TraineeActivityController {
  _TestTraineeActivityController(this.count)
    : super(
        groupRepository: InMemoryGroupRepository(),
        assignmentRepository: InMemoryClassroomAssignmentRepository(),
        announcementRepository: InMemoryClassroomAnnouncementRepository(),
        readStore: InMemoryActivityReadStore(),
      );

  int count;

  @override
  int get unreadCount => count;

  void setUnreadCount(int value) {
    count = value;
    notifyListeners();
  }
}

class _TestTeacherActivityController extends TeacherActivityController {
  _TestTeacherActivityController(
    this.count, {
    List<TeacherActivity> activities = const [],
  }) : _activities = activities,
       super(
         groupRepository: InMemoryGroupRepository(),
         assignmentRepository: InMemoryClassroomAssignmentRepository(),
         chatRepository: InMemoryChatRepository(),
         readStore: InMemoryActivityReadStore(),
       );

  int count;
  final List<TeacherActivity> _activities;
  final List<String> markedReadIds = [];

  @override
  int get unreadCount => count;

  @override
  List<TeacherActivity> get activities => _activities;

  @override
  Future<void> markRead(TeacherActivity activity) async {
    markedReadIds.add(activity.id);
    if (!activity.isRead && count > 0) count--;
    notifyListeners();
  }
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  Widget child, {
  FluentThemeData? theme,
  Size size = const Size(1100, 800),
}) {
  return FluentApp(
    theme: theme ?? AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: ScaffoldPage(content: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trainee hero promotes today recommended movement', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(
          child: SizedBox(
            width: 1100,
            child: DashboardHero(
              firstName: 'Ada',
              greeting: 'Good Morning',
              sessionCount: 3,
              recommendation: null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('✦  PRACTICE TODAY'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('Build control. Move with confidence.'), findsOneWidget);
    expect(find.text('3 sessions completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-hero-slogan')), findsOneWidget);
    final heroSlogan = tester.widget<Image>(
      find.byKey(const ValueKey('dashboard-hero-slogan')),
    );
    expect((heroSlogan.image as AssetImage).assetName, 'assets/slogan_2.png');
    expect(heroSlogan.fit, BoxFit.contain);
  });

  testWidgets('trainee hero remains overflow-free at compact width', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 800));
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: DashboardHero(
              firstName: 'Ada',
              greeting: 'Good Evening',
              sessionCount: 1,
              recommendation: null,
            ),
          ),
        ),
        size: const Size(800, 800),
      ),
    );
    await tester.pump();

    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('1 session completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-hero-slogan')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'trainee hero keeps the slogan with an expanded-sidebar-width recommendation',
    (tester) async {
      await _setSurface(tester, const Size(850, 800));
      final recommendation = buildTrainingRecommendation(
        sessions: const [],
        movements: movementCatalog,
        readyPracticeVariantFor: (movement) => movement.name == 'Normal Grip'
            ? const PracticeVariant(
                movementName: 'Normal Grip',
                trainingProp: TrainingProp.bottle,
              )
            : null,
      );

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 850,
            child: DashboardHero(
              firstName: 'Ada',
              greeting: 'Good Morning',
              sessionCount: 3,
              recommendation: recommendation,
            ),
          ),
          size: const Size(850, 800),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('dashboard-hero-slogan')),
        findsOneWidget,
      );
      final heroSlogan = tester.widget<Image>(
        find.byKey(const ValueKey('dashboard-hero-slogan')),
      );
      expect((heroSlogan.image as AssetImage).assetName, 'assets/slogan_2.png');
      expect(heroSlogan.fit, BoxFit.contain);
      expect(find.text('Continue Practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trainee hero keeps fallback CTAs overflow-free at expanded-sidebar width',
    (tester) async {
      await _setSurface(tester, const Size(850, 800));
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 850,
            child: DashboardHero(
              firstName: 'Ada',
              greeting: 'Good Evening',
              sessionCount: 1,
              recommendation: null,
            ),
          ),
          size: const Size(850, 800),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('dashboard-hero-slogan')),
        findsOneWidget,
      );
      expect(find.text('Continue Practice'), findsOneWidget);
      expect(find.text('Explore Movements'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('high contrast trainee hero drops banner art', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(
          child: SizedBox(
            width: 1100,
            child: DashboardHero(
              firstName: 'Ada',
              greeting: 'Good Morning',
              sessionCount: 0,
              recommendation: null,
            ),
          ),
        ),
        theme: AppTheme.highContrastDark,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('Start Your First Practice'), findsOneWidget);
  });

  testWidgets('dashboard header separates welcome copy from quick actions', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 1100,
          child: DashboardHeader(firstName: 'Ada', greeting: 'Good Morning'),
        ),
      ),
    );

    expect(find.text('Good Morning, Ada 👋'), findsOneWidget);
    expect(
      find.text('Keep going. Every pour builds a better you.'),
      findsOneWidget,
    );
    expect(find.text('Search movements or lessons…'), findsNothing);
    expect(find.byIcon(FluentIcons.ringer), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-header-slogan')),
      findsOneWidget,
    );
    final headerSlogan = tester.widget<Image>(
      find.byKey(const ValueKey('dashboard-header-slogan')),
    );
    expect((headerSlogan.image as AssetImage).assetName, 'assets/slogan_1.png');
  });

  testWidgets('dashboard bell opens its notification panel in place', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 1100,
          child: DashboardHeader(firstName: 'Ada', greeting: 'Good Morning'),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('dashboard-header-notifications')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('dashboard-notifications-flyout')),
      findsOneWidget,
    );
    expect(find.text('Notifications'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'trainee notification bell reflects unread changes and caps at 99+',
    (tester) async {
      await _setSurface(tester, const Size(1100, 800));
      final activity = _TestTraineeActivityController(0);
      addTearDown(activity.dispose);
      await tester.pumpWidget(
        _app(
          ChangeNotifierProvider<TraineeActivityController>.value(
            value: activity,
            child: const SizedBox(
              width: 1100,
              child: DashboardHeader(
                firstName: 'Ada',
                greeting: 'Good Morning',
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(
          const ValueKey('dashboard-header-notification-unread-badge'),
        ),
        findsNothing,
      );

      activity.setUnreadCount(12);
      await tester.pump();
      expect(find.text('12'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('dashboard-header-notification-unread-badge'),
        ),
        findsOneWidget,
      );

      activity.setUnreadCount(100);
      await tester.pump();
      expect(find.text('99+'), findsOneWidget);

      activity.setUnreadCount(0);
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey('dashboard-header-notification-unread-badge'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'light dashboard header keeps the notification and slogan transparent',
    (tester) async {
      await _setSurface(tester, const Size(1100, 800));
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 1100,
            child: DashboardHeader(firstName: 'Ada', greeting: 'Good Morning'),
          ),
          theme: AppTheme.light,
        ),
      );

      expect(find.text('Search movements or lessons…'), findsNothing);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('dashboard-header-slogan')),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
      final notificationFinder = find.byKey(
        const ValueKey('dashboard-header-notifications'),
      );
      final notification = tester.widget<AnimatedContainer>(
        find.descendant(
          of: notificationFinder,
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = notification.decoration! as BoxDecoration;
      expect(
        decoration.color,
        tester.element(notificationFinder).elixCardSurface,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dashboard header keeps the slogan in a narrowed workspace', (
    tester,
  ) async {
    await _setSurface(tester, const Size(420, 600));
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 420,
          child: DashboardHeader(firstName: 'Ada', greeting: 'Good Morning'),
        ),
        size: const Size(420, 600),
      ),
    );

    expect(
      find.byKey(const ValueKey('dashboard-header-slogan')),
      findsOneWidget,
    );
    expect(find.text('Search movements or lessons…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('training overview numbers use the large metric scale', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        DashboardTrainingOverview(
          stats: ProgressStats(
            totalSessions: 12,
            rubricSessionCount: 12,
            averageRubricTotal: 8.5,
            bestRubricTotal: 11,
            mostPracticedMovement: 'Normal Grip',
            sessionsByMovement: {'Normal Grip': 12},
          ),
          sessionsThisWeek: 2,
          weeklyComparison: ComparableRubricProgress.compare(
            currentScores: const [11],
            comparisonScores: const [10],
          ),
        ),
      ),
    );

    expect(find.text('Training Overview'), findsOneWidget);
    expect(find.byType(ElixEditorialHeader), findsWidgets);
    final sessions = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == '12' ||
                widget.textSpan?.toPlainText().startsWith('12') == true),
      ),
    );
    final style = sessions.style ?? sessions.textSpan!.style!;
    expect(style.fontSize, 44);
  });

  testWidgets('training overview shows neutral copy for unavailable growth', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        DashboardTrainingOverview(
          stats: const ProgressStats(
            totalSessions: 1,
            rubricSessionCount: 1,
            averageRubricTotal: 0,
            bestRubricTotal: 0,
            sessionsByMovement: {},
          ),
          sessionsThisWeek: 1,
          weeklyComparison: ComparableRubricProgress.compare(
            currentScores: const [0],
            comparisonScores: const [],
          ),
        ),
      ),
    );

    expect(find.text('Not enough data'), findsOneWidget);
    expect(find.textContaining('0% vs last week'), findsNothing);
  });

  testWidgets('training overview keeps genuine zero growth numeric', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        DashboardTrainingOverview(
          stats: const ProgressStats(
            totalSessions: 2,
            rubricSessionCount: 2,
            averageRubricTotal: 8,
            bestRubricTotal: 8,
            sessionsByMovement: {},
          ),
          sessionsThisWeek: 1,
          weeklyComparison: ComparableRubricProgress.compare(
            currentScores: const [8],
            comparisonScores: const [8],
          ),
        ),
      ),
    );

    expect(find.text('+0% vs last week'), findsOneWidget);
  });

  testWidgets("recommendation keeps coach copy and uses an eyebrow", (
    tester,
  ) async {
    await _setSurface(tester, const Size(900, 600));
    final recommendation = buildTrainingRecommendation(
      sessions: const [],
      movements: movementCatalog,
      readyPracticeVariantFor: (movement) => movement.name == 'Normal Grip'
          ? const PracticeVariant(
              movementName: 'Normal Grip',
              trainingProp: TrainingProp.bottle,
            )
          : null,
    );

    await tester.pumpWidget(
      _app(
        RecommendedPracticeCard(recommendation: recommendation, loading: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("COACH'S FOCUS"), findsOneWidget);
    expect(find.byType(ElixEyebrow), findsOneWidget);
    expect(find.byKey(ElixEyebrow.ruleKey), findsOneWidget);
    expect(find.text('Practice this'), findsNothing);
  });

  testWidgets('personal record uses metric type and milestone gold', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        DashboardTopPerformance(
          bestSession: Session(
            userId: 'u1',
            movementName: 'Normal Grip',
            difficulty: 'Easy',
            rubric: const RubricAssessment(
              technique: 3,
              stability: 3,
              completion: 3,
              propPositioning: 2,
            ),
            assessmentVersion: 2,
            durationSeconds: 60,
          ),
        ),
      ),
    );

    expect(find.text('Top Performance'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-top-performance-slogan')),
      findsOneWidget,
    );
    final slogan = tester.widget<Image>(
      find.byKey(const ValueKey('dashboard-top-performance-slogan')),
    );
    expect((slogan.image as AssetImage).assetName, 'assets/slogan_3.png');
    expect(slogan.fit, BoxFit.contain);
    final record = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().startsWith('11'),
      ),
    );
    final span = record.text as TextSpan;
    expect(span.style!.fontSize, 44);
    expect(span.style!.color, ElixSemanticColors.dark.milestone);
  });

  testWidgets('teacher dashboard chrome uses the canonical dashboard header', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    final auth = AuthService(
      repository: _SilentAuthRepository(),
      awaitInitialAuthState: () async {},
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: const TeacherDashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('TEACHER WORKSPACE'), findsOneWidget);
    expect(find.byKey(ElixEyebrow.ruleKey), findsOneWidget);
    expect(find.text('Teacher command center'), findsNothing);
    final heading = tester.widget<Text>(find.text('Dashboard'));
    expect(heading.style!.fontSize, lessThan(52));
  });

  testWidgets(
    'teacher dashboard shows teacher identity, metrics, and actions',
    (tester) async {
      await _setSurface(tester, const Size(1100, 800));
      final teacher = const User(
        id: 'teacher-1',
        firstName: 'Jiro',
        lastName: 'Lapuz',
        email: 'jiro@example.test',
        role: User.roleTeacher,
        profilePictureUrl: 'https://example.test/jiro.png',
        profileBorderId: 'cyan_orbit',
      );
      final auth = AuthService(
        repository: _SilentAuthRepository(teacher),
        awaitInitialAuthState: () async {},
      );
      final groups = InMemoryGroupRepository();
      groups.seedGroup(
        const ElixrGroup(
          id: 'group-1',
          teacherId: 'teacher-1',
          name: 'BSIT-3A',
          status: ElixrGroupStatus.active,
        ),
      );
      addTearDown(auth.dispose);
      addTearDown(groups.dispose);
      await auth.initialize();

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              Provider<GroupRepository>.value(value: groups),
            ],
            child: const TeacherDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Welcome back, Jiro Lapuz'), findsOneWidget);
      expect(find.text('Active classrooms'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Pending requests'), findsOneWidget);
      expect(find.text('Your classrooms'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('No pending requests'), findsOneWidget);
      expect(find.text('Open classroom'), findsOneWidget);
      expect(find.textContaining('roster'), findsNothing);
      expect(find.byKey(const Key('teacher_dashboard_avatar')), findsOneWidget);
      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byKey(const Key('teacher_dashboard_avatar')),
      );
      expect(avatar.equippedBorderId, 'cyan_orbit');
      expect(avatar.animateBorder, isTrue);
      expect(
        find.byKey(const Key('teacher_dashboard_open_classrooms')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_dashboard_to_review')),
        findsOneWidget,
      );
      await _setSurface(tester, const Size(420, 800));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.highContrastDark,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              Provider<GroupRepository>.value(value: groups),
            ],
            child: const TeacherDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Work to review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('teacher dashboard shows the activity bell and unread badge', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    final teacher = const User(
      id: 'teacher-1',
      firstName: 'Jiro',
      lastName: 'Lapuz',
      email: 'jiro@example.test',
      role: User.roleTeacher,
    );
    final auth = AuthService(
      repository: _SilentAuthRepository(teacher),
      awaitInitialAuthState: () async {},
    );
    final groups = InMemoryGroupRepository();
    final activity = _TestTeacherActivityController(100);
    addTearDown(auth.dispose);
    addTearDown(groups.dispose);
    addTearDown(activity.dispose);
    await auth.initialize();

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<GroupRepository>.value(value: groups),
            ChangeNotifierProvider<TeacherActivityController>.value(
              value: activity,
            ),
          ],
          child: const TeacherDashboardScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('teacher_dashboard_notifications')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-dashboard-notification-unread-badge')),
      findsOneWidget,
    );
    expect(find.text('99+'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher notification bell previews activity before navigation', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    final teacher = const User(
      id: 'teacher-1',
      firstName: 'Jiro',
      lastName: 'Lapuz',
      email: 'jiro@example.test',
      role: User.roleTeacher,
    );
    final auth = AuthService(
      repository: _SilentAuthRepository(teacher),
      awaitInitialAuthState: () async {},
    );
    final groups = InMemoryGroupRepository();
    final recentActivities = List.generate(
      6,
      (index) => TeacherActivity(
        id: 'activity-$index',
        type: index == 0
            ? TeacherActivityType.newSubmission
            : TeacherActivityType.message,
        occurredAt: DateTime.utc(2026, 1, 1, 12, index),
        title: 'Activity $index',
        description: 'Teacher notification $index',
        destination: AppRoutePaths.teacherActivityCenter,
        isRead: index > 1,
      ),
    );
    final activity = _TestTeacherActivityController(
      2,
      activities: recentActivities,
    );
    addTearDown(auth.dispose);
    addTearDown(groups.dispose);
    addTearDown(activity.dispose);
    await auth.initialize();
    final providers = MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        Provider<GroupRepository>.value(value: groups),
        ChangeNotifierProvider<TeacherActivityController>.value(
          value: activity,
        ),
      ],
      child: const TeacherDashboardScreen(),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => providers),
        GoRoute(
          path: AppRoutePaths.teacherActivityCenter,
          builder: (_, _) => const Text('Teacher activity destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('teacher_dashboard_notifications')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('teacher-dashboard-notifications-flyout')),
      findsOneWidget,
    );
    expect(find.text('Teacher activity destination'), findsNothing);
    expect(find.text('2 new'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_dashboard_notification_activity-0')),
      findsOneWidget,
    );
    final notificationList = tester.widget<ListView>(
      find.byKey(const ValueKey('teacher-dashboard-notifications-list')),
    );
    expect(notificationList.semanticChildCount, 5);

    await tester.tap(
      find.byKey(const Key('teacher_dashboard_notification_activity-0')),
    );
    await tester.pumpAndSettle();

    expect(activity.markedReadIds, ['activity-0']);
    expect(
      find.byKey(const ValueKey('teacher-dashboard-notifications-flyout')),
      findsNothing,
    );
    expect(find.text('Teacher activity destination'), findsOneWidget);
  });

  testWidgets(
    'teacher notification flyout safely renders empty and loading states',
    (tester) async {
      await _setSurface(tester, const Size(1100, 800));
      final teacher = const User(
        id: 'teacher-1',
        firstName: 'Jiro',
        lastName: 'Lapuz',
        email: 'jiro@example.test',
        role: User.roleTeacher,
      );
      final auth = AuthService(
        repository: _SilentAuthRepository(teacher),
        awaitInitialAuthState: () async {},
      );
      final groups = InMemoryGroupRepository();
      final activity = _TestTeacherActivityController(0);
      addTearDown(auth.dispose);
      addTearDown(groups.dispose);
      addTearDown(activity.dispose);
      await auth.initialize();

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              Provider<GroupRepository>.value(value: groups),
              ChangeNotifierProvider<TeacherActivityController>.value(
                value: activity,
              ),
            ],
            child: const TeacherDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('teacher_dashboard_notifications')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("You're all caught up."), findsOneWidget);
      activity.loading = true;
      activity.notifyListeners();
      await tester.pump();
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
