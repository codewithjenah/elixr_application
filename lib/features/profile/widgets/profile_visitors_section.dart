import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_visit.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/widgets/leaderboard_identity.dart';
import '../user_profile_controller.dart';

class ProfileVisitorsSection extends StatelessWidget {
  const ProfileVisitorsSection({
    super.key,
    required this.state,
    required this.visitors,
  });

  final ProfileVisitorsState state;
  final List<ProfileVisitDisplay> visitors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? AppColors.panelSurface
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile Visitors',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Players who recently viewed your profile.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (state) {
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
                for (var i = 0; i < visitors.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _VisitorRow(visitor: visitors[i]),
                ],
              ],
            ),
          },
        ],
      ),
    );
  }
}

class _VisitorRow extends StatelessWidget {
  const _VisitorRow({required this.visitor});

  final ProfileVisitDisplay visitor;

  @override
  Widget build(BuildContext context) {
    final lastVisited = visitor.visit.lastViewedAt;
    final label = lastVisited != null
        ? DateFormat.yMMMd().add_jm().format(
            DateTime.tryParse(lastVisited)?.toLocal() ?? DateTime.now(),
          )
        : 'Recently';

    return Row(
      children: [
        LeaderboardInitialsAvatar(
          initials: LeaderboardPresentation.initialsFor(visitor.displayName),
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
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
