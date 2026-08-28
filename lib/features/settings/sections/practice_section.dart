import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../services/camera_device_service.dart';
import '../../../services/settings_service.dart';
import '../widgets/practice_preferences_controller.dart';
import '../widgets/practice_preferences_editor.dart';
import '../widgets/settings_components.dart';

/// Practice Settings: mirror, camera source, and Live Practice draft editor.
class PracticeSection extends StatefulWidget {
  const PracticeSection({super.key, required this.controller});

  final PracticePreferencesController controller;

  @override
  State<PracticeSection> createState() => _PracticeSectionState();
}

class _PracticeSectionState extends State<PracticeSection> {
  bool _mirrorWriting = false;
  String? _mirrorWriteError;
  bool _soundWriting = false;
  String? _soundWriteError;
  double? _volumeDraft;
  bool _savingDraft = false;
  String? _draftSaveError;
  bool _camerasRefreshed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _camerasRefreshed) return;
      _camerasRefreshed = true;
      context.read<CameraDeviceService>().refresh(forceRefresh: true);
    });
  }

  Future<void> _onMirrorChanged(bool value) async {
    if (_mirrorWriting) return;
    setState(() {
      _mirrorWriting = true;
      _mirrorWriteError = null;
    });

    final settings = context.read<SettingsService>();
    final outcome = await settings.setCameraMirrored(value);
    if (!mounted) return;

    setState(() {
      _mirrorWriting = false;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _mirrorWriteError =
            'Could not save camera mirror preference. Try again.';
      }
    });
  }

  Future<void> _onSoundEnabledChanged(bool value) async {
    if (_soundWriting) return;
    setState(() {
      _soundWriting = true;
      _soundWriteError = null;
    });

    final settings = context.read<SettingsService>();
    final outcome = await settings.setSoundEnabled(value);
    if (!mounted) return;

    setState(() {
      _soundWriting = false;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _soundWriteError = 'Could not save sound preference. Try again.';
      }
    });
  }

  Future<void> _onVolumeChangeEnd(double value) async {
    if (_soundWriting) return;
    setState(() {
      _soundWriting = true;
      _soundWriteError = null;
      _volumeDraft = value;
    });

    final settings = context.read<SettingsService>();
    final outcome = await settings.setMusicVolume(value);
    if (!mounted) return;

    setState(() {
      _soundWriting = false;
      _volumeDraft = null;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _soundWriteError = 'Could not save volume preference. Try again.';
      }
    });
  }

  Future<void> _saveDraft() async {
    if (_savingDraft || !widget.controller.canSave) return;
    setState(() {
      _savingDraft = true;
      _draftSaveError = null;
    });

    try {
      final outcome = await widget.controller.save();
      if (!mounted) return;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        setState(() {
          _draftSaveError =
              'Could not save Live Practice preferences. Try again.';
        });
      } else if (outcome == SettingsWriteOutcome.saved) {
        await ElixDialog.success(context, 'Live Practice preferences saved.');
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() => _draftSaveError = e.message?.toString() ?? e.toString());
      }
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final cameras = context.watch<CameraDeviceService>();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsToggleRow(
                  label: 'Mirror camera feed',
                  description:
                      'Flip the camera preview horizontally, like a mirror.',
                  checked: settings.cameraMirrored,
                  onChanged: _mirrorWriting ? null : _onMirrorChanged,
                ),
                if (_mirrorWriteError != null)
                  SettingsStatusBanner(message: _mirrorWriteError!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            child: _CameraSourcePreference(
              settings: settings,
              cameras: cameras,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sound',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Control practice music and sound effects.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SettingsToggleRow(
                  label: 'Enable sound',
                  description:
                      'Mute or unmute practice music and sound effects.',
                  checked: settings.soundEnabled,
                  onChanged: _soundWriting ? null : _onSoundEnabledChanged,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Volume',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Slider(
                  value: _volumeDraft ?? settings.musicVolume,
                  min: 0.0,
                  max: 1.0,
                  label:
                      '${((_volumeDraft ?? settings.musicVolume) * 100).round()}%',
                  onChanged: !settings.soundEnabled || _soundWriting
                      ? null
                      : (value) => setState(() => _volumeDraft = value),
                  onChangeEnd: !settings.soundEnabled || _soundWriting
                      ? null
                      : _onVolumeChangeEnd,
                ),
                if (_soundWriteError != null)
                  SettingsStatusBanner(message: _soundWriteError!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Practice set',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose movements, pace, and music for Live Practice sessions.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PracticePreferencesEditor(controller: widget.controller),
                const SizedBox(height: AppSpacing.lg),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final dirty = widget.controller.isDirty;
                    final canSave = widget.controller.canSave;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton(
                          onPressed: dirty && canSave && !_savingDraft
                              ? _saveDraft
                              : null,
                          child: _savingDraft
                              ? const ProgressRing(strokeWidth: 2)
                              : const Text('Save practice preferences'),
                        ),
                        if (_draftSaveError != null)
                          SettingsStatusBanner(message: _draftSaveError!),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraSourcePreference extends StatefulWidget {
  const _CameraSourcePreference({
    required this.settings,
    required this.cameras,
  });

  final SettingsService settings;
  final CameraDeviceService cameras;

  @override
  State<_CameraSourcePreference> createState() =>
      _CameraSourcePreferenceState();
}

class _CameraSourcePreferenceState extends State<_CameraSourcePreference> {
  static const _autoValue = '__auto_select__';

  bool _writing = false;
  String? _writeError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeMigrateLegacySelection();
  }

  Future<void> _maybeMigrateLegacySelection() async {
    final settings = widget.settings;
    final cameras = widget.cameras;
    if (!settings.hasPendingLegacyCameraMigration) return;
    if (cameras.state != CameraDiscoveryState.success) return;
    if (cameras.cameras.isEmpty) return;

    final migrated = await settings.migrateLegacyCameraIndex(cameras.cameras);
    if (migrated && mounted) {
      setState(() {});
    }
  }

  Future<void> _onSelectionChanged(String? value) async {
    if (value == null || _writing) return;
    setState(() {
      _writing = true;
      _writeError = null;
    });

    final settings = widget.settings;
    final cameras = widget.cameras;
    late final SettingsWriteOutcome outcome;
    if (value == _autoValue) {
      outcome = await settings.clearCameraSelectionForAutoSelect();
    } else {
      final match = cameras.findByDeviceId(value);
      outcome = await settings.setSelectedCameraDevice(
        value,
        displayName: match?.displayName ?? settings.selectedCameraDisplayName,
      );
    }

    if (!mounted) return;
    setState(() {
      _writing = false;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _writeError = 'Could not save camera selection. Try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final cameras = widget.cameras;
    final selectedId = settings.selectedCameraDeviceId;
    final labels = cameras.distinguishableLabels;
    final items = <ComboBoxItem<String>>[
      const ComboBoxItem<String>(
        value: _autoValue,
        child: Text('Auto-select (Recommended)'),
      ),
      for (var i = 0; i < cameras.cameras.length; i++)
        ComboBoxItem<String>(
          value: cameras.cameras[i].deviceId,
          child: Text(labels[i]),
        ),
    ];

    final discoveryComplete =
        cameras.state == CameraDiscoveryState.success ||
        cameras.state == CameraDiscoveryState.empty;
    final selectedMissing =
        selectedId != null &&
        discoveryComplete &&
        cameras.findByDeviceId(selectedId) == null;
    if (selectedId != null && cameras.findByDeviceId(selectedId) == null) {
      final cachedName =
          settings.selectedCameraDisplayName ?? 'Selected camera';
      final label = selectedMissing ? '$cachedName — unavailable' : cachedName;
      items.add(ComboBoxItem<String>(value: selectedId, child: Text(label)));
    }

    final comboValue = selectedId ?? _autoValue;
    final statusText = _statusText(selectedId);
    final warning =
        selectedId != null &&
        cameras.state == CameraDiscoveryState.success &&
        selectedMissing;

    final autoActive = cameras.activeDeviceId != null
        ? cameras.findByDeviceId(cameras.activeDeviceId!)
        : null;

    final selectionLocked = cameras.isLoading || _writing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Camera source',
          style: AppTheme.body.copyWith(
            fontSize: 14,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the camera ELIXR will use during practice.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: ComboBox<String>(
                value: comboValue,
                items: items,
                isExpanded: true,
                onChanged: selectionLocked ? null : _onSelectionChanged,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: cameras.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.refresh, size: 16),
              onPressed: cameras.isLoading
                  ? null
                  : () async {
                      await cameras.refresh(forceRefresh: true);
                      if (!mounted) return;
                      await _maybeMigrateLegacySelection();
                    },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          statusText,
          style: AppTheme.caption.copyWith(
            color: warning || cameras.state == CameraDiscoveryState.error
                ? context.elixColors.warning
                : context.elixTextSecondary,
          ),
        ),
        if (selectedId == null &&
            cameras.state == CameraDiscoveryState.success &&
            autoActive != null) ...[
          const SizedBox(height: 4),
          Text(
            'Auto-select is currently using ${autoActive.displayName}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        if (warning) ...[
          const SizedBox(height: 4),
          Text(
            '${settings.selectedCameraDisplayName ?? 'Selected camera'} is no longer available',
            style: AppTheme.caption.copyWith(color: context.elixColors.warning),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Selection applies to your next practice session',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        if (_writeError != null) SettingsStatusBanner(message: _writeError!),
      ],
    );
  }

  String _statusText(String? selected) {
    final cameras = widget.cameras;
    switch (cameras.state) {
      case CameraDiscoveryState.idle:
      case CameraDiscoveryState.loading:
        return 'Checking cameras…';
      case CameraDiscoveryState.empty:
        return 'No usable cameras detected';
      case CameraDiscoveryState.error:
        return cameras.errorMessage ??
            'Backend unavailable — start the Python server';
      case CameraDiscoveryState.success:
        final count = cameras.cameras.length;
        return '$count camera${count == 1 ? '' : 's'} available';
    }
  }
}
