import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../router/app_route_paths.dart';
import 'teacher_sidebar.dart';

/// Dedicated Fluent shell for Teacher accounts. Does not mount trainee
/// onboarding, practice WebSocket services, or camera tutorial lifecycle.
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key, required this.child});

  final Widget child;

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  bool _sidebarCollapsed = false;

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of your ELIXR Teacher account?',
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
    if (mounted) context.go(AppRoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return ColoredBox(
      color: context.elixBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeacherSidebar(
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

/// Placeholder destination for Teacher features delivered in later phases.
class TeacherPlaceholderScreen extends StatelessWidget {
  const TeacherPlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ElixScaffoldPage(
      header: PageHeader(title: Text(title)),
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.info_solid,
                size: 48,
                color: AppColors.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: AppTheme.headingLarge.copyWith(
                  color: context.elixTextPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Available in a later ELIXR Teacher phase.',
                style: AppTheme.body.copyWith(color: context.elixTextSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal scaffold page wrapper used by Teacher shell destinations.
///
/// Defaults to a document-style [SingleChildScrollView]. Pass [scrollable]
/// `false` for viewport pages whose child owns scrolling (for example a
/// `Column` with an `Expanded` `ListView`).
class ElixScaffoldPage extends StatelessWidget {
  const ElixScaffoldPage({
    super.key,
    required this.header,
    required this.content,
    this.scrollable = true,
  });

  final PageHeader header;
  final Widget content;

  /// When true, content is wrapped in [SingleChildScrollView] with page
  /// padding. When false, content receives bounded [ScaffoldPage] height and
  /// the same padding, without an outer vertical scroll view.
  final bool scrollable;

  static const EdgeInsets _pagePadding = EdgeInsets.all(AppSpacing.lg);

  @override
  Widget build(BuildContext context) {
    final paddedContent = Padding(padding: _pagePadding, child: content);
    return ScaffoldPage(
      header: header,
      content: scrollable
          ? SingleChildScrollView(padding: _pagePadding, child: content)
          : paddedContent,
    );
  }
}
