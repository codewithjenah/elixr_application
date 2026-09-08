import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../widgets/settings_components.dart';

/// ELIXR product and founding-team information for both Settings audiences.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const _description =
      'ELIXR is a computer vision-based flairtending training application '
      'designed to help beginners learn movements through guided practice and '
      'real-time feedback.';

  static const _members = [
    _TeamMember('Jenah Ambagan', 'assets/team/jenah.jpg'),
    _TeamMember('Nicole Manaloto', 'assets/team/nicole.jpg'),
    _TeamMember('Jiro Gonzales', 'assets/team/jiro.jpg'),
    _TeamMember('Venice Bumagat', 'assets/team/venice.png'),
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 480;
          final cardWidth = twoColumns
              ? (constraints.maxWidth - AppSpacing.md) / 2
              : constraints.maxWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ABOUT ELIXR',
                style: AppTheme.eyebrow(color: context.elixColors.brandPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              ElixPanelCard(
                accent: context.elixColors.brandPrimary,
                showAccentBar: true,
                variant: ElixPanelVariant.hero,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BrandMark(),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Built for better bottle flair practice',
                            style: AppTheme.headingMedium.copyWith(
                              color: context.elixTextPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _description,
                            style: AppTheme.body.copyWith(
                              fontSize: 14,
                              height: 1.45,
                              color: context.elixTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'MEET THE TEAM',
                style: AppTheme.eyebrow(
                  color: context.elixColors.brandSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final member in _members)
                    SizedBox(
                      width: cardWidth,
                      child: _TeamMemberCard(member: member),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          );
        },
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: context.isHighContrast ? context.elixCardSurface : null,
        gradient: context.isHighContrast
            ? null
            : LinearGradient(
                colors: [
                  context.elixColors.brandPrimary.withValues(alpha: 0.28),
                  context.elixColors.brandSecondary.withValues(alpha: 0.16),
                ],
              ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : context.elixColors.brandPrimary.withValues(alpha: 0.38),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Icon(
        FluentIcons.starburst,
        size: 20,
        color: context.elixColors.brandPrimary,
      ),
    );
  }
}

class _TeamMember {
  const _TeamMember(this.name, this.imageAsset);

  final String name;
  final String imageAsset;
}

class _TeamMemberCard extends StatefulWidget {
  const _TeamMemberCard({required this.member});

  final _TeamMember member;

  @override
  State<_TeamMemberCard> createState() => _TeamMemberCardState();
}

class _TeamMemberCardState extends State<_TeamMemberCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.elixColors.brandSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: ElixMotion.duration(context, ElixMotion.micro),
        curve: ElixMotion.microCurve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(settingsRadiusLg),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : accent.withValues(alpha: _hovered ? 0.52 : 0.24),
            width: context.isHighContrast ? 2 : 1,
          ),
          boxShadow: _hovered && !context.isHighContrast
              ? [
                  BoxShadow(
                    color: context.elixColors.shadow.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: ElixPanelCard(
          accent: accent,
          expand: false,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              _MemberAvatar(member: widget.member),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.member.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Co-founder & Developer',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
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

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final _TeamMember member;

  @override
  Widget build(BuildContext context) {
    final fallback = member.name
        .split(' ')
        .map((word) => word.substring(0, 1))
        .join();
    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset(
        member.imageAsset,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(
          color: context.elixColors.interactiveSelected,
          child: Center(
            child: Text(
              fallback,
              style: AppTheme.body.copyWith(
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: '${member.name} profile photo',
      child: Container(
        width: 60,
        height: 60,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : context.elixColors.brandPrimary.withValues(alpha: 0.52),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: avatar,
      ),
    );
  }
}
