import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_visit.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/widgets/leaderboard_identity.dart';
import '../user_profile_controller.dart';
import 'profile_section_card.dart';

class ProfileVisitorsSection extends StatefulWidget {
  const ProfileVisitorsSection({
    super.key,
    required this.state,
    required this.visitors,
    required this.onVisitorTap,
    this.initialVisibleCount = 5,
  });

  final ProfileVisitorsState state;
  final List<ProfileVisitDisplay> visitors;
  final ValueChanged<ProfileVisitDisplay> onVisitorTap;
  final int initialVisibleCount;

  @override
  State<ProfileVisitorsSection> createState() => _ProfileVisitorsSectionState();
}

class _ProfileVisitorsSectionState extends State<ProfileVisitorsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canCollapse =
        widget.state == ProfileVisitorsState.loaded &&
        widget.visitors.length > widget.initialVisibleCount;
    final visibleVisitors = !canCollapse || _expanded
        ? widget.visitors
        : widget.visitors.take(widget.initialVisibleCount).toList();

    return ProfileSectionCard(
      title: 'Profile Visitors',
      subtitle: 'Players who recently viewed your profile.',
      child: switch (widget.state) {
        ProfileVisitorsState.loading => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: ProgressRing(activeColor: AppColors.primary),
          ),
        ),
        ProfileVisitorsState.empty => Text(
          'No profile visitors yet.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        ProfileVisitorsState.error => Text(
          'Could not load profile visitors.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        ProfileVisitorsState.loaded => Column(
          children: [
            for (var i = 0; i < visibleVisitors.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _VisitorRow(
                visitor: visibleVisitors[i],
                onTap: () => widget.onVisitorTap(visibleVisitors[i]),
              ),
            ],
            if (canCollapse) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: HyperlinkButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Show Less' : 'Show More'),
                ),
              ),
            ],
          ],
        ),
      },
    );
  }
}

class _VisitorRow extends StatelessWidget {
  const _VisitorRow({required this.visitor, required this.onTap});

  final ProfileVisitDisplay visitor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lastVisited = visitor.visit.lastViewedAt;
    final label = lastVisited != null
        ? DateFormat.yMMMd().add_jm().format(
            DateTime.tryParse(lastVisited)?.toLocal() ?? DateTime.now(),
          )
        : 'Recently';

    return HoverButton(
      onPressed: onTap,
      cursor: SystemMouseCursors.click,
      semanticLabel: "View ${visitor.displayName}'s profile",
      builder: (context, states) {
        final highlighted =
            states.isHovered || states.isPressed || states.isFocused;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: highlighted
                ? (context.isDarkTheme
                      ? context.elixCardSurface.withValues(alpha: 0.55)
                      : context.elixBackground.withValues(alpha: 0.85))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              LeaderboardInitialsAvatar(
                initials: LeaderboardPresentation.initialsFor(
                  visitor.displayName,
                ),
                accent: AppColors.accent,
                size: 36,
                profilePictureUrl: visitor.profilePictureUrl,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visitor.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    Text(
                      'Last visited $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                FluentIcons.chevron_right,
                size: 12,
                color: context.elixTextSecondary,
              ),
            ],
          ),
        );
      },
    );
  }
}
