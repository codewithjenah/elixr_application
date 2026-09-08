import 'package:fluent_ui/fluent_ui.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/progression/progression_catalog.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/locked_movement_mark.dart';
import '../../../core/widgets/movement_image.dart';
import 'profile_section_card.dart';

/// How completed-movement identities are presented on a given surface.
enum CompletedMovementsIdentityPolicy {
  /// Teacher/admin: show every recognized completed movement.
  authorizedFull,

  /// Trainee surfaces: hide identities the viewer has not personally revealed.
  viewerRelative,
}

class CompletedMovementsSection extends StatelessWidget {
  const CompletedMovementsSection({
    super.key,
    required this.movementNames,
    required this.identityPolicy,
    this.viewerLevel,
  });

  final List<String> movementNames;
  final CompletedMovementsIdentityPolicy identityPolicy;

  /// Viewer's personal level. Required for [viewerRelative]; ignored otherwise.
  /// Null means progression is still resolving.
  final int? viewerLevel;

  @override
  Widget build(BuildContext context) {
    final recognized = _currentMovementNames(movementNames);
    final loading =
        identityPolicy == CompletedMovementsIdentityPolicy.viewerRelative &&
        viewerLevel == null;

    if (loading) {
      return ProfileSectionCard(
        title: 'Completed Movements',
        child: Semantics(
          label: 'Loading completed movements',
          child: Text(
            'Checking completed movements…',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
        ),
      );
    }

    final revealed = <String>[];
    var hiddenCount = 0;
    if (identityPolicy == CompletedMovementsIdentityPolicy.authorizedFull) {
      revealed.addAll(recognized);
    } else {
      for (final name in recognized) {
        if (isMovementIdentityRevealed(name, viewerLevel)) {
          revealed.add(name);
        } else {
          hiddenCount++;
        }
      }
    }

    return ProfileSectionCard(
      title: 'Completed Movements',
      trailing: recognized.isEmpty
          ? null
          : Text(
              '${recognized.length}',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
      child: recognized.isEmpty
          ? Text(
              'No completed movements yet.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 520 ? 2 : 1;
                const gap = AppSpacing.sm;
                final tileWidth = (width - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final name in revealed)
                      SizedBox(
                        width: tileWidth,
                        child: _MovementTile(name: name),
                      ),
                    if (hiddenCount > 0)
                      SizedBox(
                        width: tileWidth,
                        child: _LockedSummaryTile(count: hiddenCount),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

List<String> _currentMovementNames(Iterable<String> names) {
  final unique = <String>{};
  final visible = <String>[];
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        !isRecognizedCoachingMovement(trimmed) ||
        !unique.add(trimmed)) {
      continue;
    }
    visible.add(trimmed);
  }
  visible.sort();
  return visible;
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : context.elixBorder.withValues(alpha: 0.4),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.isHighContrast
                  ? context.elixCardSurface
                  : context.elixColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: MovementImage(
              movementName: name,
              size: 28,
              paddingFactor: 0,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.elixTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedSummaryTile extends StatelessWidget {
  const _LockedSummaryTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = MovementSpoilerCopy.hiddenCompletedCount(count);
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: context.elixBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : context.elixBorder.withValues(alpha: 0.4),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            LockedMovementMark(size: 28, accent: context.elixTextSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.elixTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
