import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movement_visuals.dart';
import '../../../core/constants/movements.dart';
import '../../../core/constants/music_tracks.dart';
import '../../../core/theme/app_theme.dart';
import '../../movements/movements_presentation.dart';
import 'practice_preferences_controller.dart';

/// Presentation-only Live Practice preferences editor.
///
/// Hosts own Save / Cancel / discard chrome; this widget only mutates the
/// provided [PracticePreferencesController].
class PracticePreferencesEditor extends StatelessWidget {
  const PracticePreferencesEditor({super.key, required this.controller});

  final PracticePreferencesController controller;

  static const _intervalOptions = [15, 25, 40];
  static const _difficultyOrder = ['Easy', 'Medium', 'Hard'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final draft = controller.draft;
        final canSave = controller.canSave;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Movements',
              style: AppTheme.body.copyWith(
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final difficulty in _difficultyOrder) ...[
              _DifficultyGroup(
                difficulty: difficulty,
                orderedSelected: draft.movementNames,
                onToggle: controller.toggleMovement,
                onMove: controller.moveMovement,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (!canSave)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Select at least one movement.',
                  style: AppTheme.caption.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pace',
              style: AppTheme.body.copyWith(
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final seconds in _intervalOptions)
                  _SelectChip(
                    label: '${seconds}s',
                    selected: draft.intervalSeconds == seconds,
                    color: AppColors.accent,
                    onTap: () => controller.setInterval(seconds),
                  ),
              ],
            ),
            if (musicTrackCatalog.length > 1) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Session Music',
                style: AppTheme.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _SelectChip(
                    label: 'Shuffle',
                    selected: draft.musicTrackId == null,
                    color: AppColors.primarySoft,
                    onTap: () => controller.setMusicTrackId(null),
                  ),
                  for (final track in musicTrackCatalog)
                    _SelectChip(
                      label: track.displayName,
                      selected: draft.musicTrackId == track.id,
                      color: AppColors.primarySoft,
                      onTap: () => controller.setMusicTrackId(track.id),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DifficultyGroup extends StatelessWidget {
  const _DifficultyGroup({
    required this.difficulty,
    required this.orderedSelected,
    required this.onToggle,
    required this.onMove,
  });

  final String difficulty;
  final List<String> orderedSelected;
  final void Function(String name, bool selected) onToggle;
  final void Function(String name, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(difficulty);
    final movements = movementsByDifficulty(difficulty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            difficultySectionTitle(difficulty),
            style: AppTheme.caption.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final movement in movements)
          _MovementRow(
            name: movement.name,
            emoji: MovementVisuals.emojiFor(movement.name),
            accent: accent,
            selected: orderedSelected.contains(movement.name),
            order: orderedSelected.contains(movement.name)
                ? orderedSelected.indexOf(movement.name) + 1
                : null,
            canMoveUp:
                orderedSelected.length > 1 &&
                orderedSelected.indexOf(movement.name) > 0,
            canMoveDown:
                orderedSelected.length > 1 &&
                orderedSelected.contains(movement.name) &&
                orderedSelected.indexOf(movement.name) <
                    orderedSelected.length - 1,
            onToggle: (value) => onToggle(movement.name, value),
            onMoveUp: () => onMove(movement.name, -1),
            onMoveDown: () => onMove(movement.name, 1),
          ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.name,
    required this.emoji,
    required this.accent,
    required this.selected,
    required this.order,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final String name;
  final String emoji;
  final Color accent;
  final bool selected;
  final int? order;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            checked: selected,
            onChanged: (value) => onToggle(value ?? false),
          ),
          const SizedBox(width: 4),
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              style: AppTheme.body.copyWith(
                fontSize: 13,
                color: context.elixTextPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (order != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '#$order',
                style: AppTheme.caption.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                FluentIcons.chevron_up,
                size: 12,
                color: canMoveUp
                    ? context.elixTextSecondary
                    : context.elixBorder,
              ),
              onPressed: canMoveUp ? onMoveUp : null,
            ),
            IconButton(
              icon: Icon(
                FluentIcons.chevron_down,
                size: 12,
                color: canMoveDown
                    ? context.elixTextSecondary
                    : context.elixBorder,
              ),
              onPressed: canMoveDown ? onMoveDown : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectChip extends StatefulWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SelectChip> createState() => _SelectChipState();
}

class _SelectChipState extends State<_SelectChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? widget.color.withValues(
                    alpha: context.isDarkTheme ? 0.22 : 0.16,
                  )
                : (_hovered ? context.elixCardSurface : context.elixBackground),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? widget.color.withValues(alpha: 0.55)
                  : context.elixBorder,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? widget.color : context.elixTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
