import 'package:fluent_ui/fluent_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/music_tracks.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../services/settings_service.dart';
import 'practice_preferences_controller.dart';

/// Presentation-only Playground music preferences editor.
///
/// Hosts own Save / Cancel / discard chrome; this widget only mutates the
/// provided [PracticePreferencesController].
class PracticePreferencesEditor extends StatefulWidget {
  const PracticePreferencesEditor({
    super.key,
    required this.controller,
    this.selectMusicFile,
  });

  final PracticePreferencesController controller;
  final Future<XFile?> Function()? selectMusicFile;

  @override
  State<PracticePreferencesEditor> createState() =>
      _PracticePreferencesEditorState();
}

class _PracticePreferencesEditorState extends State<PracticePreferencesEditor> {
  bool _choosingFile = false;
  String? _fileError;

  PracticePreferencesController get controller => widget.controller;

  Future<void> _addMusic() async {
    if (_choosingFile) return;
    setState(() {
      _choosingFile = true;
      _fileError = null;
    });
    try {
      final file =
          await (widget.selectMusicFile?.call() ??
              openFile(
                acceptedTypeGroups: const <XTypeGroup>[
                  XTypeGroup(label: 'MP3 audio', extensions: <String>['mp3']),
                ],
              ));
      if (file == null) return;
      final outcome = await controller.addCustomMusicTrack(
        filePath: file.path,
        displayName: file.name,
      );
      if (!mounted) return;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        setState(() => _fileError = 'Could not save this music file.');
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _fileError = error.message?.toString());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _fileError = 'Could not add this music file.');
      }
    } finally {
      if (mounted) {
        setState(() => _choosingFile = false);
      }
    }
  }

  Future<void> _removeMusic(String id) async {
    final outcome = await controller.removeCustomMusicTrack(id);
    if (!mounted || outcome != SettingsWriteOutcome.writeFailed) return;
    setState(() => _fileError = 'Could not remove this saved music file.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final draft = controller.draft;
        final availableCustomIds = controller.availableCustomMusicTracks
            .map((track) => track.id)
            .toSet();
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
                for (final track in controller.customMusicTracks)
                  _SelectChip(
                    label: availableCustomIds.contains(track.id)
                        ? track.displayName
                        : '${track.displayName} (Unavailable)',
                    selected: draft.musicTrackId == track.id,
                    color: context.elixColors.brandPrimary,
                    onTap: availableCustomIds.contains(track.id)
                        ? () => controller.setMusicTrackId(track.id)
                        : null,
                    onRemove: () => _removeMusic(track.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Button(
              onPressed: _choosingFile ? null : _addMusic,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_choosingFile)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  else
                    const Icon(FluentIcons.music_note, size: 14),
                  const SizedBox(width: 8),
                  Text(_choosingFile ? 'Adding…' : 'Add music'),
                ],
              ),
            ),
            if (_fileError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _fileError!,
                style: AppTheme.caption.copyWith(
                  color: context.elixColors.warning,
                ),
              ),
            ],
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
    this.onRemove,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

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
      enabled: widget.onTap != null,
      selected: selected,
      label: widget.label,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        mouseCursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
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
                  if (widget.onRemove != null) ...[
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: 'Remove ${widget.label} from saved music',
                      child: IconButton(
                        icon: const Icon(FluentIcons.chrome_close, size: 11),
                        onPressed: widget.onRemove,
                      ),
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
