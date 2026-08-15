import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/onboarding/onboarding_overlay.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../theme/app_theme.dart';
import 'elix_sidebar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _sidebarCollapsed = false;
  bool _onboardingShown = false;

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of your ELIXR account?',
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('Log out'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !mounted) return;

    await context.read<AuthService>().logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final auth = context.watch<AuthService>();
    final settings = context.watch<SettingsService>();
    final tutorials = context.watch<TutorialProgressService>();

    if (auth.isAuthenticated &&
        settings.isInitialized &&
        tutorials.isInitialized &&
        !tutorials.onboardingComplete &&
        !_onboardingShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _onboardingShown) return;
        if (!context.read<AuthService>().isAuthenticated) return;
        if (!context.read<SettingsService>().isInitialized) return;
        if (context.read<TutorialProgressService>().onboardingComplete) return;
        _onboardingShown = true;
        OnboardingOverlay.show(context);
      });
    }

    return ColoredBox(
      color: context.elixBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElixSidebar(
            currentRoute: location,
            isCollapsed: _sidebarCollapsed,
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            onLogout: _confirmAndLogout,
          ),
          Expanded(child: ClipRect(child: widget.child)),
        ],
      ),
    );
  }
}
