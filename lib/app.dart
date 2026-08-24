import 'dart:async';

import 'package:elixr_core/repositories/firebase_teacher_access_code_repository.dart';
import 'package:elixr_core/repositories/teacher_access_code_repository.dart';
import 'package:elixr_core/repositories/firebase_group_repository.dart';
import 'package:elixr_core/repositories/firebase_teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/firebase_teacher_progress_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:elixr_core/repositories/coaching_note_repository.dart';
import 'package:elixr_core/repositories/firebase_coaching_note_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/leaderboard_repository.dart';
import 'data/repositories/public_profile_repository.dart';
import 'data/repositories/classroom_assignment_repository.dart';
import 'data/repositories/assignment_submission_repository.dart';
import 'data/repositories/firebase_assignment_submission_repository.dart';
import 'data/repositories/firebase_classroom_assignment_repository.dart';
import 'data/repositories/firebase_teacher_movement_repository.dart';
import 'data/repositories/teacher_movement_repository.dart';
import 'features/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/camera_device_service.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';
import 'services/tutorial_progress_service.dart';
import 'services/join_code_resolver.dart';
import 'services/join_link_service.dart';

class ElixrApp extends StatefulWidget {
  ElixrApp({
    super.key,
    TeacherAccessCodeRepository? teacherAccessCodeRepository,
  }) : teacherAccessCodeRepository =
           teacherAccessCodeRepository ?? FirebaseTeacherAccessCodeRepository();

  final TeacherAccessCodeRepository teacherAccessCodeRepository;

  @override
  State<ElixrApp> createState() => _ElixrAppState();
}

class _ElixrAppState extends State<ElixrApp> {
  late final AuthService _authService;
  late final SettingsService _settingsService;
  late final CameraDeviceService _cameraDeviceService;
  late final TutorialProgressService _tutorialProgressService;
  late final PublicProfileRepository _publicProfileRepository;
  late final TeacherRelationshipRepository _teacherRelationshipRepository;
  late final GroupRepository _groupRepository;
  late final JoinCodeResolver _joinCodeResolver;
  late final JoinLinkService _joinLinkService;
  late final GoRouter _router;
  bool _splashFinished = false;

  @override
  void initState() {
    super.initState();
    _publicProfileRepository = PublicProfileRepository();
    _teacherRelationshipRepository = FirebaseTeacherRelationshipRepository();
    _groupRepository = FirebaseGroupRepository();
    _joinCodeResolver = JoinCodeResolver(
      groupRepository: _groupRepository,
      relationshipRepository: _teacherRelationshipRepository,
    );
    _joinLinkService = JoinLinkService();
    _authService = AuthService(
      leaderboardRepository: LeaderboardRepository(),
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
        Provider<GroupRepository>.value(value: _groupRepository),
        Provider<JoinCodeResolver>.value(value: _joinCodeResolver),
        Provider<TeacherMovementRepository>(
          create: (_) => FirebaseTeacherMovementRepository(),
        ),
        Provider<ClassroomAssignmentRepository>(
          create: (_) => FirebaseClassroomAssignmentRepository(),
        ),
        ProxyProvider<
          ClassroomAssignmentRepository,
          AssignmentSubmissionRepository
        >(
          update: (_, classroom, previous) =>
              previous ??
              FirebaseAssignmentSubmissionRepository(classroom: classroom),
        ),
        Provider<CoachingNoteRepository>(
          create: (_) => FirebaseCoachingNoteRepository(),
        ),
        Provider<TeacherProgressRepository>(
          create: (_) => FirebaseTeacherProgressRepository(),
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
                    if (!_splashFinished || auth.isLoading) {
                      return SplashScreen(
                        authReady: !auth.isLoading,
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
