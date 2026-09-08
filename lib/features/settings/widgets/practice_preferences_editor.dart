import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/music_tracks.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import 'practice_preferences_controller.dart';

/// Presentation-only Playground music preferences editor.
///
/// Hosts own Save / Cancel / discard chrome; this widget only mutates the
/// provided [PracticePreferencesController].
class PracticePreferencesEditor extends StatelessWidget {
  const PracticePreferencesEditor({super.key, required this.controller});

  final PracticePreferencesController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final draft = controller.draft;
        if (musicTrackCatalog.length <= 1) {
          return Text(
            'Session music is not available on this device.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
        );
      },
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
