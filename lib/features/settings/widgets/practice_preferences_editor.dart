import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movements.dart';
import '../../../core/constants/music_tracks.dart';
import '../../../core/progression/practice_variant.dart';
import '../../../core/progression/progression_access.dart';
import '../../../core/progression/progression_catalog.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/movement.dart';
import '../../../services/trainee_progression_service.dart';
import '../../../services/tutorial_progress_service.dart';
import '../../movements/movements_presentation.dart';
import 'practice_preferences_controller.dart';
import 'practice_setlist_access.dart';

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
        final selected = draft.practiceVariants;

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
                orderedSelected: selected,
                onToggle: controller.toggleVariant,
                onMove: controller.moveVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (!canSave)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Select at least one ready practice variant.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixColors.error,
                  ),
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
                    color: context.elixColors.brandSecondary,
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
                    color: context.elixColors.brandPrimary,
                    onTap: () => controller.setMusicTrackId(null),
                  ),
                  for (final track in musicTrackCatalog)
                    _SelectChip(
                      label: track.displayName,
                      selected: draft.musicTrackId == track.id,
                      color: context.elixColors.brandPrimary,
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
  final List<PracticeVariant> orderedSelected;
  final void Function(PracticeVariant variant, bool selected) onToggle;
  final void Function(PracticeVariant variant, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final accent = context.isHighContrast
        ? context.elixTextPrimary
        : difficultyAccentColor(difficulty);
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
        for (final movement in movements) ...[
          if (movement.supportedProps.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Row(
                children: [
                  MovementImage(movementName: movement.name, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      movement.name,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final prop in movement.supportedProps)
              _VariantRow(
                movement: movement,
                variant: PracticeVariant(
                  movementName: movement.name,
                  trainingProp: prop,
                ),
                title: prop.displayLabel,
                showImage: false,
                accent: accent,
                orderedSelected: orderedSelected,
                onToggle: onToggle,
                onMove: onMove,
              ),
          ] else
            _VariantRow(
              movement: movement,
              variant: PracticeVariant(
                movementName: movement.name,
                trainingProp: movement.supportedProps.first,
              ),
              title: movement.name,
              showImage: true,
              accent: accent,
              orderedSelected: orderedSelected,
              onToggle: onToggle,
              onMove: onMove,
            ),
        ],
      ],
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.movement,
    required this.variant,
    required this.title,
    required this.showImage,
    required this.accent,
    required this.orderedSelected,
    required this.onToggle,
    required this.onMove,
  });

  final Movement movement;
  final PracticeVariant variant;
  final String title;
  final bool showImage;
  final Color accent;
  final List<PracticeVariant> orderedSelected;
  final void Function(PracticeVariant variant, bool selected) onToggle;
  final void Function(PracticeVariant variant, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = orderedSelected.indexWhere(
      (entry) => entry.persistenceKey == variant.persistenceKey,
    );
    final selected = selectedIndex >= 0;
    final progression = Provider.of<TraineeProgressionService?>(
      context,
      listen: true,
    );
    final tutorials = Provider.of<TutorialProgressService?>(
      context,
      listen: true,
    );
    final access = (progression == null || tutorials == null)
        ? ProgressionAccessResult.personalLoading
        : evaluatePersonal(
            variant: variant,
            currentLevel: progression.currentLevelOrNull,
            tutorialCompleted: tutorials.isInitialized
                ? tutorials.hasCompletedLesson(
                    variant.movementName,
                    variant.trainingProp,
                  )
                : null,
          );
    final state = practiceSetlistSelectionState(access);
    final canAdd = practiceSetlistCanAdd(state);
    final canRemove = practiceSetlistCanRemove(state, selected: selected);
    final checkboxEnabled = selected ? canRemove : canAdd;
    final status = practiceSetlistStatusLabel(
      state,
      requiredLevel: requiredLevelFor(variant),
    );
    final order = selected ? selectedIndex + 1 : null;

    return Padding(
      padding: EdgeInsets.only(
        left: showImage ? 0 : 22,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        children: [
          Checkbox(
            checked: selected,
            onChanged: checkboxEnabled
                ? (value) => onToggle(variant, value ?? false)
                : null,
          ),
          const SizedBox(width: 4),
          if (showImage) ...[
            MovementImage(movementName: movement.name, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.body.copyWith(
                    fontSize: 13,
                    color: checkboxEnabled || selected
                        ? context.elixTextPrimary
                        : context.elixTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (status != null)
                  Text(
                    status,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (order != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.isHighContrast
                    ? context.elixCardSurface
                    : accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: context.isHighContrast
                    ? Border.all(color: context.elixBorder)
                    : null,
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
                color: selectedIndex > 0
                    ? context.elixTextSecondary
                    : context.elixBorder,
              ),
              onPressed: selectedIndex > 0
                  ? () => onMove(variant, -1)
                  : null,
            ),
            IconButton(
              icon: Icon(
                FluentIcons.chevron_down,
                size: 12,
                color:
                    selectedIndex >= 0 &&
                        selectedIndex < orderedSelected.length - 1
                    ? context.elixTextSecondary
                    : context.elixBorder,
              ),
              onPressed:
                  selectedIndex >= 0 &&
                      selectedIndex < orderedSelected.length - 1
                  ? () => onMove(variant, 1)
                  : null,
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final highContrast = context.isHighContrast;
    final highlighted = _hovered || _focused;
    final fill = highContrast
        ? context.elixCardSurface
        : selected
        ? widget.color.withValues(alpha: context.isDarkTheme ? 0.22 : 0.16)
        : highlighted
        ? context.elixColors.interactiveHover
        : context.elixBackground;
    final borderColor = _focused
        ? context.elixColors.focusRing
        : highContrast
        ? context.elixBorder
        : selected
        ? widget.color.withValues(alpha: 0.55)
        : context.elixBorder;

    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      label: widget.label,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: ElixMotion.duration(context, ElixMotion.micro),
              curve: ElixMotion.microCurve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: _focused
                      ? (highContrast
                            ? ElixFocus.ringWidthHighContrast
                            : ElixFocus.ringWidth)
                      : (highContrast ? ElixFocus.ringWidth : 1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? (highContrast
                                ? context.elixTextPrimary
                                : widget.color)
                          : context.elixTextSecondary,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Icon(
                      FluentIcons.check_mark,
                      size: 12,
                      color: highContrast
                          ? context.elixTextPrimary
                          : widget.color,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
