import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/constants/app_spacing.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:elixr_application/core/widgets/elix_stat_card.dart';
import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/achievements/widgets/achievement_card.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_controller.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_screen.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_controller.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_screen.dart';
import 'package:elixr_application/features/calendar/widgets/calendar_header.dart';
import 'package:elixr_application/features/calendar/widgets/calendar_summary_cards.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_podium.dart';
import 'package:elixr_application/features/learning/learning_center_screen.dart';
import 'package:elixr_application/features/learning/movement_lesson.dart';
import 'package:elixr_application/features/movements/movements_presentation.dart';
import 'package:elixr_application/features/movements/widgets/movements_header.dart';
import 'package:elixr_application/features/progress/widgets/progress_overview_stats.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_detail_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _SilentAuthRepository implements AuthRepositoryBase {
  @override
  Future<User?> loadPersistedUser() async => null;
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

GroupAssignment _assignment({required String id, String groupId = 'g1'}) {
  return GroupAssignment(
    id: id,
    teacherId: 'teacher-1',
    groupId: groupId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Hand Stall',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    officialMovementName: 'Hand Stall',
  );
}

LeaderboardEntry _entry({
  required String id,
  required String name,
  int xp = 300,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: 8,
    scoreSum: 80,
    averageScore: 80,
    bestScore: 90,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('learning hero uses Manrope page title, not Bahnschrift', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(_app(const LearningCenterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Help & Tutorials'), findsOneWidget);
    expect(find.text('LEARNING CENTER'), findsOneWidget);
    expect(find.byType(ElixEditorialHeader), findsWidgets);
    expect(find.byType(ElixEyebrow), findsWidgets);

    final heading = tester.widget<Text>(find.text('Help & Tutorials'));
    expect(heading.style!.fontSize, 36);
    expect(heading.style!.fontFamily, isNot(AppTheme.brandFontFamily));
    expect(heading.style!.fontFamily, ElixTypography.fontFamily);

    expect(
      find.text(
        'Learn the flow, understand your score, and build every movement with confidence.',
      ),
      findsOneWidget,
    );

    final lessonCount = movementCatalog.where((m) => m.enabled).length;
    final metric = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(ElixStatCard),
            matching: find.text('$lessonCount'),
          )
          .first,
    );
    expect(metric.style!.fontSize, 44);
  });

  testWidgets('learning hero uses compact 30px title under 900px', (
    tester,
  ) async {
    await _setSurface(tester, const Size(800, 800));
    await tester.pumpWidget(
      _app(const LearningCenterScreen(), size: const Size(800, 800)),
    );
    await tester.pumpAndSettle();

    final heading = tester.widget<Text>(find.text('Help & Tutorials'));
    expect(heading.style!.fontSize, 30);
  });

  testWidgets('high contrast learning hero drops icon gradient and glow', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(const LearningCenterScreen(), theme: AppTheme.highContrastDark),
    );
    await tester.pumpAndSettle();

    final icon = find.byIcon(FluentIcons.education);
    expect(icon, findsOneWidget);
    final container = tester.widget<Container>(
      find.ancestor(of: icon, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
  });

  testWidgets('movement lesson uses compact editorial heading', (tester) async {
    await _setSurface(tester, const Size(1180, 900));
    await tester.pumpWidget(
      _app(
        const MovementLessonScreen(
          movement: 'Claw Grip',
          difficulty: 'Easy',
          prop: TrainingProp.bottle,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MOVEMENT LESSON'), findsOneWidget);
    expect(find.byType(ElixEyebrow), findsWidgets);
    final heading = tester.widget<Text>(find.text('Claw Grip'));
    expect(heading.style!.fontSize, 24);
    expect(find.text('Back to tutorials'), findsOneWidget);
  });

  testWidgets('assigned movements list uses standard editorial title', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    final controller = AssignedMovementsController(
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(AssignedMovementsScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('Assigned Movements'), findsOneWidget);
    expect(
      find.text(
        'Classroom work from your approved groups, split into Official ELIXR and Teacher-created. Public profile privacy does not hide these assignments.',
      ),
      findsOneWidget,
    );
    expect(find.byType(ElixEditorialHeader), findsOneWidget);
    final heading = tester.widget<Text>(find.text('Assigned Movements'));
    expect(heading.style!.fontSize, 36);
  });

  testWidgets('assignment detail uses compact editorial title', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      GroupMembership(
        id: GroupMembership.documentId(groupId: 'g1', traineeId: 'trainee-1'),
        groupId: 'g1',
        teacherId: 'teacher-1',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.approved,
      ),
    );
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-a'));
    final controller = AssignmentDetailController(
      assignmentId: 'asg-a',
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      _app(
        AssignmentDetailScreen(assignmentId: 'asg-a', controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Hand Stall'), findsWidgets);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('BSHM 4A'), findsOneWidget);
    final heading = tester.widget<Text>(find.text('Hand Stall').first);
    expect(heading.style!.fontSize, 24);
  });

  testWidgets(
    'assignment detail scroll reaches the page edge and keeps the content gutter',
    (tester) async {
      await _setSurface(tester, const Size(1100, 800));
      final groups = InMemoryGroupRepository();
      addTearDown(groups.dispose);
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      final controller =
          AssignmentDetailController(
              assignmentId: 'asg-a',
              traineeId: 'trainee-1',
              groupRepository: groups,
              assignmentRepository: assignments,
            )
            ..assignment = _assignment(id: 'asg-a')
            ..authorized = true;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          AssignmentDetailScreen(assignmentId: 'asg-a', controller: controller),
        ),
      );
      await tester.pump();

      final scrollRect = tester.getRect(
        find.byKey(const Key('assignment_detail_work_scroll')),
      );
      final workCardRect = tester.getRect(find.byType(ElixPanelCard).last);

      expect(scrollRect.right, closeTo(1100, 0.1));
      expect(
        workCardRect.right,
        closeTo(scrollRect.right - AppSpacing.lg, 0.1),
      );
    },
  );

  testWidgets('movements practiced count uses the large metric scale', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const MovementsHeader(
          summary: MovementsSummary(
            practicedCount: 4,
            totalMovements: 10,
            totalSessions: 9,
            rubricSessionCount: 9,
            overallAverageRubric: 8.5,
          ),
        ),
      ),
    );

    final practiced = tester.widget<Text>(find.text('4 / 10'));
    expect(practiced.style!.fontSize, 44);
  });

  testWidgets('calendar summaries use metric type and milestone streak gold', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            CalendarHeader(
              visibleMonth: DateTime(2026, 8),
              onPreviousMonth: () {},
              onNextMonth: () {},
              onToday: () {},
            ),
            const CalendarSummaryCards(
              plannedDays: 2,
              completedDays: 1,
              adherencePercent: 50,
              planStreak: 7,
            ),
          ],
        ),
      ),
    );

    expect(find.text('August 2026'), findsOneWidget);
    final planned = tester.widget<Text>(find.text('2'));
    expect(planned.style!.fontSize, 44);
    final streak = tester.widget<Text>(find.text('7'));
    expect(streak.style!.fontSize, 44);
    expect(streak.style!.color, ElixSemanticColors.dark.milestone);
    expect(streak.style!.color, isNot(AppColors.warning));
  });

  testWidgets('high contrast calendar summaries drop shadow', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const CalendarSummaryCards(
          plannedDays: 2,
          completedDays: 1,
          adherencePercent: 50,
          planStreak: 7,
        ),
        theme: AppTheme.highContrastDark,
      ),
    );

    final label = find.text('Planned Days');
    final container = tester.widget<Container>(
      find.ancestor(of: label, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
  });

  testWidgets('leaderboard rank 1 uses milestone gold and metric XP', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(
      _app(
        LeaderboardPodium(
          podium: [
            _entry(id: '1', name: 'Gold Player', xp: 300),
            _entry(id: '2', name: 'Silver Player', xp: 275),
            _entry(id: '3', name: 'Bronze Player', xp: 250),
          ],
          currentUserId: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rank = tester.widget<Text>(find.text('★ Top 1'));
    expect(rank.style!.color, ElixSemanticColors.dark.milestone);
    expect(rank.style!.color, isNot(AppColors.warning));

    final xp = tester.widget<Text>(find.text('300 XP'));
    expect(xp.style!.fontSize, 44);
    expect(xp.style!.color, ElixSemanticColors.dark.milestone);
  });

  testWidgets('progress overview uses metric type and milestone best gold', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await tester.pumpWidget(
      _app(
        const ProgressOverviewStats(
          overallPerformanceLabel: 'Proficient',
          averageLabel: 'Average Rubric',
          averageValue: '8.5 / 12',
          bestLabel: 'Best Rubric',
          bestValue: '11 / 12',
          totalSessions: 12,
          mostPracticed: 'Normal Grip',
        ),
      ),
    );

    expect(find.byType(ElixStatCard), findsWidgets);
    final best = tester.widget<Text>(find.text('11 / 12'));
    expect(best.style!.fontSize, 44);
    expect(best.style!.color, ElixSemanticColors.dark.milestone);
    final sessions = tester.widget<Text>(find.text('12'));
    expect(sessions.style!.fontSize, 44);
    expect(find.text('Overall Performance'), findsOneWidget);
    expect(find.text('Most Practiced'), findsOneWidget);
  });

  testWidgets('claimed achievement chrome uses milestone gold', (tester) async {
    await _setSurface(tester, const Size(1100, 800));
    final view = buildAchievementViewData(
      definition: achievementById('first_steps')!,
      sessions: const [],
      leaderboardEntry: null,
      claimedAchievementIds: {'first_steps'},
    );

    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 220,
          width: 420,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );

    expect(find.text('Claimed'), findsWidgets);
    final chip = tester.widget<Text>(find.text('Claimed').first);
    expect(chip.style!.color, ElixSemanticColors.dark.milestone);
    expect(chip.style!.color, isNot(AppColors.success));
  });

  testWidgets('teacher student detail chrome uses compact editorial title', (
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
          child: const TeacherStudentDetailScreen(traineeId: 't1'),
        ),
      ),
    );
    await tester.pump();

    final header = tester.widget<ElixEditorialPageHeader>(
      find.byType(ElixEditorialPageHeader),
    );
    expect(header.variant, ElixEditorialHeaderVariant.compact);
    final heading = tester.widget<Text>(find.text('Student'));
    expect(heading.style!.fontSize, 24);
  });
}
