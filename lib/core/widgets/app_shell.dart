import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/onboarding/onboarding_overlay.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final settings = context.watch<SettingsService>();

    if (settings.isInitialized &&
        !settings.hasSeenOnboarding &&
        !_onboardingShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _onboardingShown) return;
        if (!context.read<SettingsService>().isInitialized) return;
        if (context.read<SettingsService>().hasSeenOnboarding) return;
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
            onLogout: () async {
              await context.read<AuthService>().logout();
              if (context.mounted) context.go('/login');
            },
          ),
          Expanded(child: ClipRect(child: widget.child)),
        ],
      ),
    );
  }
}
