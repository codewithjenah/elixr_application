import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_toast.dart';
import '../../../services/camera_device_service.dart';
import '../../../services/settings_service.dart';
import '../widgets/camera_source_preference.dart';
import '../widgets/practice_preferences_controller.dart';
import '../widgets/practice_preferences_editor.dart';
import '../widgets/settings_components.dart';

/// Session setup: mirror, camera source, and Playground music preferences.
class PracticeSection extends StatefulWidget {
  const PracticeSection({super.key, required this.controller});

  final PracticePreferencesController controller;

  @override
  State<PracticeSection> createState() => _PracticeSectionState();
}

class _PracticeSectionState extends State<PracticeSection> {
  bool _mirrorWriting = false;
  String? _mirrorWriteError;
  bool _savingDraft = false;
  String? _draftSaveError;
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
          _draftSaveError = 'Could not save session settings. Try again.';
        });
      } else if (outcome == SettingsWriteOutcome.saved) {
        ElixToast.showSuccess(context, message: 'Session settings saved.');
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
            child: CameraSourcePreference(settings: settings, cameras: cameras),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Endless Mode music',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose music for Endless Mode runs.',
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
                        ElixPrimaryButton(
                          label: 'Save session settings',
                          dense: true,
                          expanded: false,
                          isLoading: _savingDraft,
                          onPressed: dirty && canSave && !_savingDraft
                              ? _saveDraft
                              : null,
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
