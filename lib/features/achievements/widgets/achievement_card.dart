import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/achievement.dart';
import '../../../data/models/profile_border.dart';

const _kAchievementPreviewExtent = 92.0;
const _kAchievementArtworkExtent = 68.0;

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
      AchievementState.inProgress => AppColors.accent,
      AchievementState.locked => context.elixTextSecondary,
    };
  }

  Color _previewPlateColor(BuildContext context, Color accentTint) {
    final base = context.isDarkTheme
        ? AppColors.background.withValues(alpha: 0.84)
        : AppColors.cardSurfaceLight.withValues(alpha: 0.96);
    return Color.alphaBlend(accentTint.withValues(alpha: 0.1), base);
  }

  Widget _buildAchievementPreview(BuildContext context, Color accentTint) {
    return SizedBox(
      key: Key('achievement-preview-${widget.view.definition.id}'),
      width: _kAchievementPreviewExtent,
      height: _kAchievementPreviewExtent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    accentTint.withValues(alpha: _locked ? 0.07 : 0.18),
                    accentTint.withValues(alpha: _locked ? 0.02 : 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: accentTint.withValues(alpha: _locked ? 0.12 : 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: accentTint.withValues(alpha: _locked ? 0.02 : 0.12),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.contain,
            child: ProfileBorderFrame(
              size: _kAchievementArtworkExtent,
              equippedBorderId: widget.view.definition.rewardBorderId,
              animate: !_locked,
              child: ColoredBox(
                color: _previewPlateColor(context, accentTint),
                child: Center(
                  child: Image.asset(
                    widget.view.definition.iconAssetPath,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    semanticLabel: widget.view.definition.title,
                  ),
                ),
              ),
            ),
          ),
        ],
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

    final cardBorderColor = _claimable
        ? accent.withValues(alpha: active ? 0.65 : 0.42)
        : Color.alphaBlend(
            accent.withValues(alpha: _locked ? 0.04 : 0.13),
            context.elixBorder.withValues(alpha: isDark ? 0.78 : 1),
          );
    final cardSurface = context.elixCardSurface.withValues(
      alpha: _locked ? 0.78 : 1,
    );

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
          onExit: (_) {
            if (_hovered) setState(() => _hovered = false);
          },
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      accent.withValues(
                        alpha: active
                            ? (isDark ? 0.16 : 0.09)
                            : (isDark ? 0.08 : 0.045),
                      ),
                      cardSurface,
                    ),
                    cardSurface,
                    Color.alphaBlend(
                      borderAccent.withValues(alpha: isDark ? 0.035 : 0.025),
                      cardSurface,
                    ),
                  ],
                  stops: const [0, 0.55, 1],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: cardBorderColor,
                  width: _focused ? 1.6 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark
                          ? (active ? 0.3 : 0.16)
                          : (active ? 0.1 : 0.05),
                    ),
                    blurRadius: active ? 20 : 10,
                    offset: Offset(0, active ? 8 : 4),
                  ),
                  if (active)
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
                      blurRadius: 22,
                      spreadRadius: -4,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned(
                      right: -42,
                      top: -54,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              borderAccent.withValues(
                                alpha: _locked ? 0.025 : 0.09,
                              ),
                              borderAccent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 18,
                      bottom: 18,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: accent.withValues(
                            alpha: _locked
                                ? 0.35
                                : _claimed
                                ? 0.55
                                : 0.9,
                          ),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.32),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildAchievementPreview(context, borderAccent),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.view.definition.title,
                                            style: AppTheme.body.copyWith(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: context.elixTextPrimary
                                                  .withValues(
                                                    alpha: _locked ? 0.82 : 1,
                                                  ),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _StateChip(state: state),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _categoryLabel(
                                        widget.view.definition.category,
                                      ),
                                      style: AppTheme.caption.copyWith(
                                        fontSize: 9.5,
                                        letterSpacing: 0.7,
                                        color: AppColors.accent.withValues(
                                          alpha: _locked ? 0.7 : 1,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.view.definition.description,
                                      style: AppTheme.bodySecondary.copyWith(
                                        color: context.elixTextSecondary
                                            .withValues(
                                              alpha: _locked ? 0.78 : 1,
                                            ),
                                        fontSize: 12.5,
                                        height: 1.35,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                alpha: _locked
                                    ? (isDark ? 0.025 : 0.018)
                                    : (isDark ? 0.055 : 0.035),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accent.withValues(
                                  alpha: _locked ? 0.08 : 0.15,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'PROGRESS',
                                      style: AppTheme.caption.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.7,
                                        color: context.elixTextSecondary,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${widget.view.progress.current} / ${widget.view.progress.target}',
                                      style: AppTheme.caption.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: context.elixTextPrimary
                                            .withValues(
                                              alpha: _locked ? 0.8 : 1,
                                            ),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 6,
                                    child: Stack(
                                      children: [
                                        Container(
                                          color: context.elixBorder.withValues(
                                            alpha: 0.42,
                                          ),
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: widget
                                              .view
                                              .progress
                                              .normalizedProgress,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  accent.withValues(
                                                    alpha: _locked ? 0.4 : 0.72,
                                                  ),
                                                  accent.withValues(
                                                    alpha: _locked ? 0.58 : 1,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (border != null) ...[
                                Container(
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: borderAccent.withValues(
                                      alpha: _locked ? 0.06 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: borderAccent.withValues(
                                        alpha: _locked ? 0.1 : 0.22,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    FluentIcons.trophy2,
                                    size: 11,
                                    color: borderAccent.withValues(
                                      alpha: _locked ? 0.6 : 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${border.displayName} frame',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.caption.copyWith(
                                      color: borderAccent.withValues(
                                        alpha: _locked ? 0.7 : 1,
                                      ),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ] else
                                const Spacer(),
                              if (_claimable) ...[
                                const SizedBox(width: AppSpacing.sm),
                                FilledButton(
                                  onPressed: widget.claiming
                                      ? null
                                      : _handleClaim,
                                  style: ButtonStyle(
                                    backgroundColor:
                                        WidgetStateProperty.resolveWith((
                                          states,
                                        ) {
                                          if (states.isDisabled) {
                                            return AppColors.primary.withValues(
                                              alpha: 0.45,
                                            );
                                          }
                                          if (states.isHovered) {
                                            return AppColors.primarySoft;
                                          }
                                          return AppColors.primary;
                                        }),
                                    padding: WidgetStateProperty.all(
                                      const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                    ),
                                    shape: WidgetStateProperty.all(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  child: widget.claiming
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: ProgressRing(strokeWidth: 2),
                                        )
                                      : const Text(
                                          'Claim',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                ),
                              ],
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
      AchievementCategory.sessions => 'SESSIONS',
      AchievementCategory.score => 'SCORE',
      AchievementCategory.exploration => 'EXPLORATION',
      AchievementCategory.consistency => 'CONSISTENCY',
      AchievementCategory.specialization => 'SPECIALIZATION',
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
      AchievementState.inProgress => ('In Progress', AppColors.accent),
      AchievementState.claimable => ('Claimable', AppColors.primary),
      AchievementState.claimed => ('Claimed', AppColors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: state == AchievementState.inProgress ? 0.09 : 0.12,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(
            alpha: state == AchievementState.claimed
                ? 0.28
                : state == AchievementState.inProgress
                ? 0.28
                : 0.45,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 5),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color.withValues(
                alpha: state == AchievementState.inProgress ? 0.9 : 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
