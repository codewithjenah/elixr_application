import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'elix_sidebar.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return ColoredBox(
      color: context.elixBackground,
      child: Row(
        children: [
          ElixSidebar(
            currentRoute: location,
            onLogout: () async {
              await context.read<AuthService>().logout();
              if (context.mounted) context.go('/login');
            },
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
