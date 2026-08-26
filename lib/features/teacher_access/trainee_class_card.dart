import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';

/// Pink/purple pairs from the ELIXR palette. Classes stay distinct without
/// leaving the product colors.
const _classAccentPairs = <(Color, Color)>[
  (AppColors.primary, AppColors.accent),
  (AppColors.accent, AppColors.accentSoft),
  (AppColors.primarySoft, AppColors.accent),
  (AppColors.accentSoft, AppColors.primary),
];

/// Stable brand accent for a class card or detail hero.
TraineeClassAccent traineeClassAccent(String groupId) {
  var hash = 0;
  for (final code in groupId.codeUnits) {
    hash = (hash + code) & 0x7fffffff;
  }
  final pair = _classAccentPairs[hash % _classAccentPairs.length];
  return TraineeClassAccent(start: pair.$1, end: pair.$2);
}

@immutable
class TraineeClassAccent {
  const TraineeClassAccent({required this.start, required this.end});

  final Color start;
  final Color end;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, Color.lerp(start, end, 0.42)!, end],
  );
}

/// Compact class card. Opens the class detail page.
class TraineeClassCard extends StatelessWidget {
  const TraineeClassCard({
    super.key,
    required this.groupId,
    required this.className,
    required this.teacherDisplayName,
    required this.onOpen,
  });

  final String groupId;
  final String className;
  final String teacherDisplayName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final accent = traineeClassAccent(groupId);
    return ElixHoverSurface(
      borderRadius: 18,
      onTap: onOpen,
      child: Container(
        key: Key('teacher_access_group_$groupId'),
        height: 214,
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: highContrast
                ? context.elixBorder
                : Color.alphaBlend(
                    accent.start.withValues(alpha: isDark ? 0.28 : 0.18),
                    context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
                  ),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: accent.start.withValues(alpha: isDark ? 0.16 : 0.1),
                    blurRadius: 22,
                    spreadRadius: -8,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TraineeClassHero(
                  accent: accent,
                  title: className,
                  subtitle: teacherDisplayName,
                  compact: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        FluentIcons.education,
                        size: 13,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Open classwork',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.elixTextPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      FluentIcons.chevron_right,
                      size: 12,
                      color: AppColors.primary.withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pink-to-purple class hero used by the card and the class detail page.
class TraineeClassHero extends StatelessWidget {
  const TraineeClassHero({
    super.key,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final TraineeClassAccent accent;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final titleStyle =
        (compact ? AppTheme.headingMedium : AppTheme.headingLarge).copyWith(
          color: Colors.white,
          fontSize: compact ? 20 : 28,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.3,
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: highContrast ? accent.start : null,
            gradient: highContrast ? null : accent.gradient,
          ),
        ),
        if (!highContrast) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x26FFFFFF), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            right: compact ? -28 : -36,
            top: compact ? -36 : -48,
            child: IgnorePointer(
              child: Container(
                width: compact ? 128 : 180,
                height: compact ? 128 : 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
            ),
          ),
          Positioned(
            right: compact ? 36 : 72,
            bottom: compact ? -42 : -56,
            child: IgnorePointer(
              child: Container(
                width: compact ? 92 : 130,
                height: compact ? 92 : 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 36 : 44,
                height: compact ? 36 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: highContrast ? 0.2 : 0.16,
                  ),
                  borderRadius: BorderRadius.circular(compact ? 11 : 13),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  FluentIcons.education,
                  size: compact ? 16 : 20,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              SizedBox(height: compact ? 6 : 8),
              Row(
                children: [
                  Icon(
                    FluentIcons.contact,
                    size: compact ? 12 : 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: compact ? 12 : 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
