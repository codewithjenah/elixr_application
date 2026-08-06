import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/achievement.dart';
import '../../../data/models/profile_border.dart';

class AchievementCard extends StatefulWidget {
  const AchievementCard({
    super.key,
    required this.view,
    required this.claiming,
    required this.onClaim,
  });

  final AchievementViewData view;
  final bool claiming;
  final VoidCallback onClaim;

  @override
  State<AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends State<AchievementCard> {
  bool _hovered = false;
  bool _focused = false;

  bool get _locked => widget.view.state == AchievementState.locked;
  bool get _claimable => widget.view.state == AchievementState.claimable;
  bool get _claimed => widget.view.state == AchievementState.claimed;
  bool get _interactive => _claimable && !widget.claiming;

  Color _accentColor(BuildContext context) {
    return switch (widget.view.state) {
      AchievementState.claimable => AppColors.primary,
      AchievementState.claimed => AppColors.success,
      AchievementState.inProgress => AppColors.warning,
      AchievementState.locked => context.elixTextSecondary,
    };
  }

  Color _previewPlateColor(BuildContext context, Color accentTint) {
    final base = context.isDarkTheme
        ? AppColors.background.withValues(alpha: 0.84)
        : AppColors.cardSurfaceLight.withValues(alpha: 0.96);
    return Color.alphaBlend(accentTint.withValues(alpha: 0.1), base);
  }

  Color _previewGlyphColor(BuildContext context) {
    return _locked ? context.elixTextSecondary : context.elixTextPrimary;
  }

  Widget _buildTrophyPreview(BuildContext context, Color accentTint) {
    final glyphColor = _previewGlyphColor(context);
    // Keep a fixed layout slot; ornamental frames scale down so the
    // fixed-height achievement grid never overflows.
    return SizedBox(
      width: 44,
      height: 44,
      child: FittedBox(
        fit: BoxFit.contain,
        child: ProfileBorderFrame(
          size: 36,
          equippedBorderId: widget.view.definition.rewardBorderId,
          animate: true,
          child: ColoredBox(
            color: _previewPlateColor(context, accentTint),
            child: Center(
              child: Icon(
                FluentIcons.trophy2,
                size: 20,
                color: glyphColor,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(
                      alpha: context.isDarkTheme ? 0.32 : 0.1,
                    ),
                    blurRadius: 1.5,
                    offset: const Offset(0, 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _semanticAction {
    if (_claimable && !widget.claiming) return 'Claim achievement';
    if (_claimed) return 'Claimed';
    if (_locked) return 'Locked';
    return 'In progress';
  }

  void _handleClaim() {
    if (!_interactive) return;
    widget.onClaim();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.view.state;
    final accent = _accentColor(context);
    final border = profileBorderById(widget.view.definition.rewardBorderId);
    final borderAccent = border == null
        ? accent
        : Color(border.primaryColorValue);
    final active = _interactive && (_hovered || _focused);
    final isDark = context.isDarkTheme;

    return Semantics(
      button: _interactive,
      enabled: !_locked,
      label:
          '${widget.view.definition.title}. '
          '${_stateLabel(state)}. '
          '${widget.view.progress.current} of ${widget.view.progress.target}. '
          '$_semanticAction',
      child: FocusableActionDetector(
        enabled: _interactive,
        onShowFocusHighlight: (focused) {
          setState(() => _focused = focused);
        },
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: _interactive
            ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _handleClaim();
                    return null;
                  },
                ),
              }
            : const <Type, Action<Intent>>{},
        child: MouseRegion(
          onEnter: (_) {
            if (_interactive) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          cursor: _interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: _interactive ? _handleClaim : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, active ? -2.0 : 0.0, 0),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: isDark ? 0.08 : 0.05)
                    : context.elixCardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _claimable
                      ? accent.withValues(alpha: active ? 0.65 : 0.45)
                      : _claimed
                      ? accent.withValues(alpha: active ? 0.5 : 0.35)
                      : active
                      ? accent.withValues(alpha: 0.4)
                      : context.elixBorder.withValues(alpha: isDark ? 0.7 : 1),
                  width: _focused ? 1.6 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark
                          ? (active ? 0.3 : 0.16)
                          : (active ? 0.1 : 0.05),
                    ),
                    blurRadius: active ? 12 : 6,
                    offset: Offset(0, active ? 4 : 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 3, color: accent),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTrophyPreview(context, borderAccent),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.view.definition.title,
                                      style: AppTheme.body.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: context.elixTextPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      _categoryLabel(
                                        widget.view.definition.category,
                                      ),
                                      style: AppTheme.caption.copyWith(
                                        fontSize: 10,
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StateChip(state: state),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.view.definition.description,
                            style: AppTheme.bodySecondary.copyWith(
                              color: context.elixTextSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                children: [
                                  Container(
                                    color: context.elixBorder.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor:
                                        widget.view.progress.normalizedProgress,
                                    child: Container(color: accent),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${widget.view.progress.current} / ${widget.view.progress.target}',
                                style: AppTheme.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: context.elixTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              if (border != null) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    border.displayName,
                                    textAlign: TextAlign.end,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.caption.copyWith(
                                      color: Color(border.primaryColorValue),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: AppSpacing.sm),
                              _buildFooterAction(context, accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterAction(BuildContext context, Color accent) {
    if (_claimable) {
      return FilledButton(
        onPressed: widget.claiming ? null : _handleClaim,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
        ),
        child: widget.claiming
            ? const SizedBox(
                width: 14,
                height: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            : const Text('Claim', style: TextStyle(fontSize: 11)),
      );
    }

    final (label, color) = switch (widget.view.state) {
      AchievementState.claimed => ('Claimed', AppColors.success),
      AchievementState.locked => ('Locked', context.elixTextSecondary),
      AchievementState.inProgress => ('In progress', AppColors.warning),
      AchievementState.claimable => ('Claimable', AppColors.primary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  static String _stateLabel(AchievementState state) {
    return switch (state) {
      AchievementState.locked => 'Locked',
      AchievementState.inProgress => 'In progress',
      AchievementState.claimable => 'Claimable',
      AchievementState.claimed => 'Claimed',
    };
  }

  static String _categoryLabel(AchievementCategory category) {
    return switch (category) {
      AchievementCategory.sessions => 'Sessions',
      AchievementCategory.score => 'Score',
      AchievementCategory.exploration => 'Exploration',
      AchievementCategory.consistency => 'Consistency',
      AchievementCategory.specialization => 'Specialization',
    };
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final AchievementState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      AchievementState.locked => ('Locked', context.elixTextSecondary),
      AchievementState.inProgress => ('In Progress', AppColors.warning),
      AchievementState.claimable => ('Claimable', AppColors.primary),
      AchievementState.claimed => ('Claimed', AppColors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
