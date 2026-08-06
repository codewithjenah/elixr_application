import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/leaderboard_repository.dart';
import 'data/repositories/public_profile_repository.dart';
import 'features/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/camera_device_service.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';

class ElixrApp extends StatefulWidget {
  const ElixrApp({super.key});

  @override
  State<ElixrApp> createState() => _ElixrAppState();
}

class _ElixrAppState extends State<ElixrApp> {
  late final AuthService _authService;
  late final SettingsService _settingsService;
  late final CameraDeviceService _cameraDeviceService;
  late final PublicProfileRepository _publicProfileRepository;
  late final GoRouter _router;
  bool _splashFinished = false;

  @override
  void initState() {
    super.initState();
    _publicProfileRepository = PublicProfileRepository();
    _authService = AuthService(
      leaderboardRepository: LeaderboardRepository(),
      publicProfileRepository: _publicProfileRepository,
    )..initialize();
    _settingsService = SettingsService()..initialize();
    _cameraDeviceService = CameraDeviceService();
    _router = AppRouter.create(_authService);
  }

  @override
  void dispose() {
    _cameraDeviceService.dispose();
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
        ChangeNotifierProvider(
          create: (_) =>
              SessionService(publicProfileRepository: _publicProfileRepository),
        ),
        Provider<PublicProfileRepository>.value(
          value: _publicProfileRepository,
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return FluentApp.router(
            title: AppConstants.appName,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: _router,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return Consumer<AuthService>(
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
              );
            },
          );
        },
      ),
    );
  }
}
