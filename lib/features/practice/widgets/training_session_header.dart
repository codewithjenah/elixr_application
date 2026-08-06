import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/websocket_service.dart';
import 'training_connection_badge.dart';

Color trainingDifficultyColor(String difficulty) {
  switch (difficulty.toLowerCase()) {
    case 'easy':
      return AppColors.success;
    case 'medium':
      return AppColors.warning;
    case 'hard':
      return AppColors.error;
    default:
      return AppColors.primarySoft;
  }
}

class TrainingSessionHeader extends StatelessWidget {
  const TrainingSessionHeader({
    super.key,
    required this.onBack,
    required this.title,
    required this.statusPill,
    required this.instruction,
    required this.connectionState,
    this.connecting = false,
    this.wideLayout = true,
    this.statusPillColor,
    this.trailing,
  });

  final VoidCallback onBack;
  final String title;
  final String statusPill;
  final String instruction;
  final WebSocketConnectionState connectionState;
  final bool connecting;
  final bool wideLayout;
  final Color? statusPillColor;

  /// Optional header action (e.g. "Build Your Set"). Rendered next to the
  /// title on wide layouts, and alongside the connection badge otherwise.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pillColor = statusPillColor ?? AppColors.primarySoft;
    final badge = TrainingConnectionBadge(
      state: connectionState,
      connecting: connecting,
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: AppTheme.headingLarge.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                  height: 1.15,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _DifficultyChip(label: statusPill, color: pillColor),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          instruction,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
            height: 1.35,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Padding(
      key: const ValueKey('practice-training-header'),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: wideLayout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HeaderBackButton(onPressed: onBack),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: titleBlock),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
                const SizedBox(width: AppSpacing.md),
                badge,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderBackButton(onPressed: onBack),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: titleBlock),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [badge, ?trailing],
                ),
              ],
            ),
    );
  }
}

class _HeaderBackButton extends StatefulWidget {
  const _HeaderBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_HeaderBackButton> createState() => _HeaderBackButtonState();
}

class _HeaderBackButtonState extends State<_HeaderBackButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final surface = isDark
        ? const Color(0xFF1E1A28)
        : context.elixBorder.withValues(alpha: 0.12);

    return Semantics(
      button: true,
      label: 'Back',
      child: Tooltip(
        message: 'Back',
        child: Focus(
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() {
                  _hovering = false;
                  _pressed = false;
                }),
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: widget.onPressed,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _pressed
                          ? surface.withValues(alpha: 0.9)
                          : _hovering
                          ? surface.withValues(alpha: 0.85)
                          : surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: focused
                            ? AppColors.primary.withValues(alpha: 0.65)
                            : context.elixBorder.withValues(
                                alpha: isDark ? 0.5 : 0.35,
                              ),
                        width: focused ? 1.5 : 1,
                      ),
                      boxShadow: _hovering && !_pressed
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      FluentIcons.chrome_back,
                      size: 16,
                      color: _hovering || focused
                          ? AppColors.primary
                          : context.elixTextPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
