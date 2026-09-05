import 'dart:async';

import 'package:elixr_core/repositories/firebase_teacher_access_code_repository.dart';
import 'package:elixr_core/repositories/teacher_access_code_repository.dart';
import 'package:elixr_core/repositories/faculty_directory_repository.dart';
import 'package:elixr_core/repositories/firebase_faculty_directory_repository.dart';
import 'package:elixr_core/repositories/firebase_group_repository.dart';
import 'package:elixr_core/repositories/firebase_teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/firebase_teacher_progress_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:elixr_core/repositories/firebase_teacher_evidence_repository.dart';
import 'package:elixr_core/repositories/teacher_evidence_repository.dart';
import 'package:elixr_core/repositories/chat_repository.dart';
import 'package:elixr_core/repositories/firebase_chat_repository.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
import 'package:elixr_core/repositories/firebase_classroom_announcement_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/leaderboard_repository.dart';
import 'data/repositories/public_profile_repository.dart';
import 'data/repositories/classroom_assignment_repository.dart';
import 'data/repositories/activity_learning_material_repository.dart';
import 'data/repositories/firebase_activity_learning_material_repository.dart';
import 'data/repositories/assignment_submission_repository.dart';
import 'data/repositories/firebase_assignment_submission_repository.dart';
import 'data/repositories/firebase_classroom_assignment_repository.dart';
import 'data/repositories/firebase_teacher_movement_repository.dart';
import 'data/repositories/teacher_movement_repository.dart';
import 'features/teacher/activity_center/activity_read_store.dart';
import 'features/teacher/activity_center/teacher_activity_controller.dart';
import 'features/trainee/activity_center/trainee_activity_controller.dart';
import 'features/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/camera_device_service.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';
import 'services/tutorial_progress_service.dart';
import 'services/join_code_resolver.dart';
import 'services/join_link_service.dart';
import 'services/message_unread_service.dart';

class ElixrApp extends StatefulWidget {
  ElixrApp({
    super.key,
    TeacherAccessCodeRepository? teacherAccessCodeRepository,
    FacultyDirectoryRepository? facultyDirectoryRepository,
  }) : teacherAccessCodeRepository =
           teacherAccessCodeRepository ?? FirebaseTeacherAccessCodeRepository(),
       facultyDirectoryRepository =
           facultyDirectoryRepository ?? FirebaseFacultyDirectoryRepository();

  final TeacherAccessCodeRepository teacherAccessCodeRepository;
  final FacultyDirectoryRepository facultyDirectoryRepository;

  @override
  State<ElixrApp> createState() => _ElixrAppState();
}

class _ElixrAppState extends State<ElixrApp> {
  late final AuthService _authService;
  late final SettingsService _settingsService;
  late final CameraDeviceService _cameraDeviceService;
  late final TutorialProgressService _tutorialProgressService;
  late final PublicProfileRepository _publicProfileRepository;
  late final LeaderboardRepository _leaderboardRepository;
  late final TeacherRelationshipRepository _teacherRelationshipRepository;
  late final GroupRepository _groupRepository;
  late final TeacherEvidenceRepository _teacherEvidenceRepository;
  late final JoinCodeResolver _joinCodeResolver;
  late final JoinLinkService _joinLinkService;
  late final ChatRepository _chatRepository;
  late final GoRouter _router;
  bool _splashFinished = false;

  @override
  void initState() {
    super.initState();
    _publicProfileRepository = PublicProfileRepository();
    _leaderboardRepository = LeaderboardRepository();
    _teacherRelationshipRepository = FirebaseTeacherRelationshipRepository();
    _groupRepository = FirebaseGroupRepository();
    _teacherEvidenceRepository = FirebaseTeacherEvidenceRepository();
    _joinCodeResolver = JoinCodeResolver(groupRepository: _groupRepository);
    _joinLinkService = JoinLinkService();
    _chatRepository = FirebaseChatRepository();
    _authService = AuthService(
      leaderboardRepository: _leaderboardRepository,
      publicProfileRepository: _publicProfileRepository,
      joinLinkService: _joinLinkService,
    );
    unawaited(_authService.initialize());
    _settingsService = SettingsService()..initialize();
    _cameraDeviceService = CameraDeviceService();
    _tutorialProgressService = TutorialProgressService();
    // Subscription setup is synchronous on the first call, so cold links are
    // retained before the router begins evaluating redirects.
    unawaited(_joinLinkService.initialize());
    _router = AppRouter.create(
      _authService,
      _tutorialProgressService,
      _joinLinkService,
    );
  }

  @override
  void dispose() {
    _cameraDeviceService.dispose();
    _joinLinkService.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authService),
        ChangeNotifierProvider.value(value: _settingsService),
        ChangeNotifierProvider.value(value: _cameraDeviceService),
        ChangeNotifierProvider.value(value: _joinLinkService),
        Provider<ChatRepository>.value(value: _chatRepository),
        Provider<ClassroomAnnouncementRepository>(
          create: (_) => FirebaseClassroomAnnouncementRepository(),
        ),
        Provider<ActivityReadStore>(create: (_) => FileActivityReadStore()),
        ChangeNotifierProxyProvider<AuthService, MessageUnreadService>(
          create: (_) => MessageUnreadService(repository: _chatRepository),
          update: (_, auth, unread) {
            unread ??= MessageUnreadService(repository: _chatRepository);
            unread.setUser(auth.currentUser?.id);
            return unread;
          },
        ),
        ChangeNotifierProxyProvider<AuthService, TutorialProgressService>(
          create: (_) => _tutorialProgressService,
          update: (_, auth, tutorial) {
            tutorial ??= _tutorialProgressService;
            // Teachers do not use trainee tutorial/onboarding state.
            final userId = auth.currentUser?.isTrainee == true
                ? auth.currentUser?.id
                : null;
            unawaited(tutorial.setUser(userId));
            return tutorial;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => SessionService(
            publicProfileRepository: _publicProfileRepository,
            teacherRelationshipRepository: _teacherRelationshipRepository,
          ),
        ),
        Provider<PublicProfileRepository>.value(
          value: _publicProfileRepository,
        ),
        Provider<TeacherRelationshipRepository>.value(
          value: _teacherRelationshipRepository,
        ),
        Provider<TeacherAccessCodeRepository>.value(
          value: widget.teacherAccessCodeRepository,
        ),
        Provider<FacultyDirectoryRepository>.value(
          value: widget.facultyDirectoryRepository,
        ),
        Provider<GroupRepository>.value(value: _groupRepository),
        Provider<JoinCodeResolver>.value(value: _joinCodeResolver),
        Provider<TeacherMovementRepository>(
          create: (_) => FirebaseTeacherMovementRepository(),
        ),
        Provider<ClassroomAssignmentRepository>(
          create: (_) => FirebaseClassroomAssignmentRepository(),
        ),
        Provider<ActivityLearningMaterialRepository>(
          create: (_) => FirebaseActivityLearningMaterialRepository(),
        ),
        ChangeNotifierProxyProvider<AuthService, TeacherActivityController>(
          create: (context) => TeacherActivityController(
            groupRepository: context.read<GroupRepository>(),
            assignmentRepository: context.read<ClassroomAssignmentRepository>(),
            chatRepository: context.read<ChatRepository>(),
            readStore: context.read<ActivityReadStore>(),
            publicProfileRepository: context.read<PublicProfileRepository>(),
          ),
          update: (context, auth, controller) {
            controller ??= TeacherActivityController(
              groupRepository: context.read<GroupRepository>(),
              assignmentRepository: context
                  .read<ClassroomAssignmentRepository>(),
              chatRepository: context.read<ChatRepository>(),
              readStore: context.read<ActivityReadStore>(),
              publicProfileRepository: context.read<PublicProfileRepository>(),
            );
            controller.setTeacher(
              auth.currentUser?.isTeacher == true ? auth.currentUser?.id : null,
            );
            return controller;
          },
        ),
        ChangeNotifierProxyProvider<AuthService, TraineeActivityController>(
          create: (context) => TraineeActivityController(
            groupRepository: context.read<GroupRepository>(),
            assignmentRepository: context.read<ClassroomAssignmentRepository>(),
            announcementRepository: context
                .read<ClassroomAnnouncementRepository>(),
            readStore: context.read<ActivityReadStore>(),
          ),
          update: (context, auth, controller) {
            controller ??= TraineeActivityController(
              groupRepository: context.read<GroupRepository>(),
              assignmentRepository: context
                  .read<ClassroomAssignmentRepository>(),
              announcementRepository: context
                  .read<ClassroomAnnouncementRepository>(),
              readStore: context.read<ActivityReadStore>(),
            );
            controller.setTrainee(
              auth.currentUser?.isTrainee == true ? auth.currentUser?.id : null,
            );
            return controller;
          },
        ),
        ProxyProvider<
          ClassroomAssignmentRepository,
          AssignmentSubmissionRepository
        >(
          update: (_, classroom, previous) =>
              previous ??
              FirebaseAssignmentSubmissionRepository(classroom: classroom),
        ),
        Provider<TeacherProgressRepository>(
          create: (_) => FirebaseTeacherProgressRepository(),
        ),
        Provider<LeaderboardRepository>.value(value: _leaderboardRepository),
        Provider<TeacherEvidenceRepository>.value(
          value: _teacherEvidenceRepository,
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return FluentApp.router(
            title: AppConstants.appName,
            theme: settings.highContrast
                ? AppTheme.highContrastLight
                : AppTheme.light,
            darkTheme: settings.highContrast
                ? AppTheme.highContrastDark
                : AppTheme.dark,
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: _router,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(settings.textScale)),
                child: Consumer<AuthService>(
                  builder: (context, auth, _) {
                    final startupFailed =
                        auth.initializationState ==
                        AuthInitializationState.failed;
                    if (!_splashFinished || auth.isLoading || startupFailed) {
                      return SplashScreen(
                        authReady:
                            auth.initializationState ==
                            AuthInitializationState.ready,
                        startupError: auth.initializationFailure?.message,
                        onRetry: startupFailed
                            ? () => unawaited(auth.initialize())
                            : null,
                        onFinished: () {
                          if (mounted) setState(() => _splashFinished = true);
                        },
                      );
                    }
                    return child ?? const SizedBox.shrink();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
