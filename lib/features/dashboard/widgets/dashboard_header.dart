import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Welcome and quick-navigation chrome above the trainee dashboard.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.firstName,
    required this.greeting,
  });

  final String firstName;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the slogan visible when the expanded sidebar reduces the
        // dashboard's available width. The search control yields first.
        final showSearch = constraints.maxWidth >= 820;
        // The header slogan is a persistent piece of dashboard chrome. Text
        // and search yield space before it does, so sidebar state never makes
        // the slogan disappear.
        const showSlogan = true;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, $firstName 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sectionTitle(
                      context,
                      color: context.elixTextPrimary,
                    ).copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Keep going. Every pour builds a better you.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.supporting(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (showSearch) ...[
              const SizedBox(width: 24),
              _QuickSearch(onPressed: () => context.go('/movements')),
            ],
            const SizedBox(width: 12),
            _HeaderIconButton(
              icon: FluentIcons.ringer,
              tooltip: 'Notifications',
              onPressed: () => context.go('/activity-center'),
            ),
            if (showSlogan && !context.isHighContrast) ...[
              const SizedBox(width: 18),
              const _HeaderSlogan(),
            ],
          ],
        );
      },
    );
  }
}

class _HeaderSlogan extends StatelessWidget {
  const _HeaderSlogan();

  @override
  Widget build(BuildContext context) {
    // Keep the tall three-line artwork contained in the compact header slot.
    return Semantics(
      image: true,
      label: 'Skills pour further',
      child: SizedBox(
        width: 92,
        height: 76,
        child: Image.asset(
          'assets/slogan_1.png',
          key: const ValueKey('dashboard-header-slogan'),
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _QuickSearch extends StatefulWidget {
  const _QuickSearch({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_QuickSearch> createState() => _QuickSearchState();
}

class _QuickSearchState extends State<_QuickSearch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 330,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: context.isHighContrast
                ? context.elixCardSurface
                : const Color(
                    0xFF171424,
                  ).withValues(alpha: _hovered ? 0.96 : 0.82),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.isHighContrast
                  ? context.elixBorder
                  : AppColors.accent.withValues(alpha: _hovered ? 0.42 : 0.20),
              width: context.isHighContrast ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.search,
                size: 15,
                color: context.elixTextSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search movements or lessons…',
                  style: AppTheme.supporting(color: context.elixTextSecondary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: context.elixBorder.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Ctrl K',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.isHighContrast
                  ? context.elixCardSurface
                  : const Color(
                      0xFF171424,
                    ).withValues(alpha: _hovered ? 0.96 : 0.82),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.isHighContrast
                    ? context.elixBorder
                    : AppColors.accent.withValues(
                        alpha: _hovered ? 0.42 : 0.20,
                      ),
                width: context.isHighContrast ? 2 : 1,
              ),
            ),
            child: Icon(widget.icon, size: 18, color: context.elixTextPrimary),
          ),
        ),
      ),
    );
  }
}
