import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movement_visuals.dart';
import '../../../core/constants/movements.dart';
import '../../../core/constants/music_tracks.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../services/settings_service.dart';
import '../../movements/movements_presentation.dart';

/// "Build Your Set" dialog: lets the user pick and order the Just Dance
/// rotation setlist, the rotation pace, and session background music.
///
/// Purely a settings editor — saving never scores, locks, or gates the
/// underlying freeform session.
class MovementSetlistDialog {
  const MovementSetlistDialog._();

  /// Shows the dialog. Resolves to `true` when the user saved changes,
  /// `false`/`null` when dismissed without saving.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => const Center(child: _MovementSetlistDialogBody()),
    );
  }
}

class _MovementSetlistDialogBody extends StatefulWidget {
  const _MovementSetlistDialogBody();

  @override
  State<_MovementSetlistDialogBody> createState() =>
      _MovementSetlistDialogBodyState();
}

class _MovementSetlistDialogBodyState
    extends State<_MovementSetlistDialogBody> {
  static const _intervalOptions = [15, 25, 40];
  static const _difficultyOrder = ['Easy', 'Medium', 'Hard'];

  late List<String> _orderedSelected;
  late int _intervalSeconds;
  String? _musicTrackId;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _orderedSelected = List.of(settings.justDanceMovementNames);
    _intervalSeconds = settings.justDanceIntervalSeconds;
    _musicTrackId = settings.selectedMusicTrackId;
  }

  bool get _canSave => _orderedSelected.isNotEmpty;

  void _toggleMovement(String name, bool selected) {
    setState(() {
      if (selected) {
        if (!_orderedSelected.contains(name)) {
          _orderedSelected.add(name);
        }
      } else {
        _orderedSelected.remove(name);
      }
    });
  }

  void _moveMovement(String name, int delta) {
    final index = _orderedSelected.indexOf(name);
    if (index < 0) return;
    final target = index + delta;
    if (target < 0 || target >= _orderedSelected.length) return;
    setState(() {
      final entry = _orderedSelected.removeAt(index);
      _orderedSelected.insert(target, entry);
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final settings = context.read<SettingsService>();
    await settings.setJustDanceSetlist(_orderedSelected);
    await settings.setJustDanceIntervalSeconds(_intervalSeconds);
    await settings.setSelectedMusicTrackId(_musicTrackId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return ElixDialog(
      title: 'Build Your Set',
      subtitle: 'Choose the movements, pace, and music for Live Practice',
      icon: FluentIcons.music_in_collection,
      iconColor: AppColors.primary,
      maxWidth: 560,
      scrollableContent: true,
      content: Column(
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
            _buildDifficultyGroup(context, difficulty),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (!_canSave)
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
                  selected: _intervalSeconds == seconds,
                  color: AppColors.accent,
                  onTap: () => setState(() => _intervalSeconds = seconds),
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
                  selected: _musicTrackId == null,
                  color: AppColors.primarySoft,
                  onTap: () => setState(() => _musicTrackId = null),
                ),
                for (final track in musicTrackCatalog)
                  _SelectChip(
                    label: track.displayName,
                    selected: _musicTrackId == track.id,
                    color: AppColors.primarySoft,
                    onTap: () => setState(() => _musicTrackId = track.id),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElixPrimaryButton(
          label: 'Save',
          expanded: false,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }

  Widget _buildDifficultyGroup(BuildContext context, String difficulty) {
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
            selected: _orderedSelected.contains(movement.name),
            order: _orderedSelected.contains(movement.name)
                ? _orderedSelected.indexOf(movement.name) + 1
                : null,
            canMoveUp:
                _orderedSelected.length > 1 &&
                _orderedSelected.indexOf(movement.name) > 0,
            canMoveDown:
                _orderedSelected.length > 1 &&
                _orderedSelected.contains(movement.name) &&
                _orderedSelected.indexOf(movement.name) <
                    _orderedSelected.length - 1,
            onToggle: (value) => _toggleMovement(movement.name, value),
            onMoveUp: () => _moveMovement(movement.name, -1),
            onMoveDown: () => _moveMovement(movement.name, 1),
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
