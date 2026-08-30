import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/onboarding/onboarding_overlay.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../theme/app_theme.dart';
import 'elix_dialog.dart';
import 'elix_primary_button.dart';
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
    final shouldLogout = await ElixDialog.show<bool>(
      context,
      title: 'Log out?',
      icon: FluentIcons.sign_out,
      content: Text(
        'Are you sure you want to log out of your ELIXR account?',
        style: AppTheme.body.copyWith(
          fontSize: 14,
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        Button(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        ElixPrimaryButton(
          label: 'Log out',
          expanded: false,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
      uniformActionSize: const Size(128, 56),
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
        auth.currentUser?.isTrainee == true &&
        settings.isInitialized &&
        tutorials.isInitialized &&
        !tutorials.onboardingComplete &&
        !_onboardingShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _onboardingShown) return;
        if (!context.read<AuthService>().isAuthenticated) return;
        if (context.read<AuthService>().currentUser?.isTrainee != true) return;
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
