import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/constants/app_constants.dart';
import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/repositories/progress_repository.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_hero.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_top_performance.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_training_overview.dart';
import 'package:elixr_application/features/dashboard/widgets/recommended_practice_card.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:elixr_application/features/teacher/dashboard/teacher_dashboard_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _SilentAuthRepository implements AuthRepositoryBase {
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

TextSpan _headlineSpan(WidgetTester tester, String plain) {
  final heading = tester.widget<Text>(
    find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == plain,
    ),
  );
  return heading.textSpan! as TextSpan;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trainee hero keeps the tagline on one smaller desktop line', (
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

    expect(find.byType(ElixEditorialHeader), findsOneWidget);
    expect(
      find.text(AppConstants.appTagline, findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Good Morning, Ada', findRichText: true), findsOneWidget);
    expect(
      find.text('Build consistency, one movement at a time.'),
      findsOneWidget,
    );
    expect(find.text('3 sessions completed'), findsOneWidget);

    final span = _headlineSpan(tester, AppConstants.appTagline);
    expect(span.style!.fontSize, 44);
    expect(span.style!.color, Colors.white);
    expect((span.children!.last as TextSpan).style!.color, AppColors.primary);
    expect(
      tester
          .widget<Text>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.textSpan?.toPlainText() == AppConstants.appTagline,
            ),
          )
          .maxLines,
      1,
    );

    final greeting = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Good Morning, Ada',
      ),
    );
    expect(greeting.text.style!.fontSize, 16);
  });

  testWidgets('trainee hero uses a smaller compact one-line headline', (
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

    final span = _headlineSpan(tester, AppConstants.appTagline);
    expect(span.style!.fontSize, 36);
    expect(
      tester
          .widget<Text>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.textSpan?.toPlainText() == AppConstants.appTagline,
            ),
          )
          .maxLines,
      1,
    );
    expect(find.text('1 session completed'), findsOneWidget);
  });

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
    expect(find.byType(ElixEditorialHeader), findsOneWidget);
    expect(find.text('Start Recommended Practice'), findsOneWidget);
  });

  testWidgets('training overview numbers use the large metric scale', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const DashboardTrainingOverview(
          stats: ProgressStats(
            totalSessions: 12,
            rubricSessionCount: 12,
            averageRubricTotal: 8.5,
            bestRubricTotal: 11,
            mostPracticedMovement: 'Normal Grip',
            sessionsByMovement: {'Normal Grip': 12},
          ),
          sessionsThisWeek: 2,
          weeklyTrendPercent: 10,
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

  testWidgets("recommendation keeps coach copy and uses an eyebrow", (
    tester,
  ) async {
    await _setSurface(tester, const Size(900, 600));
    final recommendation = buildTrainingRecommendation(
      sessions: const [],
      movements: movementCatalog,
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
    expect(find.text('Practice this'), findsOneWidget);
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

  testWidgets('teacher dashboard chrome uses a concise command center header', (
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
    final heading = tester.widget<Text>(find.text('Teacher command center'));
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
      expect(find.text('Active groups'), findsOneWidget);
      expect(find.text('Approved students'), findsOneWidget);
      expect(find.text('Pending requests'), findsOneWidget);
      expect(find.byKey(const Key('teacher_dashboard_avatar')), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_dashboard_open_classrooms')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_dashboard_to_review')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
