import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/settings_service.dart';
import '../widgets/settings_components.dart';

/// Shared audio preferences for every authenticated ELIXR role.
class SoundSection extends StatefulWidget {
  const SoundSection({super.key});

  @override
  State<SoundSection> createState() => _SoundSectionState();
}

class _SoundSectionState extends State<SoundSection> {
  bool _writing = false;
  String? _writeError;
  double? _musicVolumeDraft;
  double? _notificationVolumeDraft;

  Future<void> _save({
    required Future<SettingsWriteOutcome> Function(SettingsService settings)
    write,
    required String failureMessage,
  }) async {
    if (_writing) return;
    setState(() {
      _writing = true;
      _writeError = null;
    });

    try {
      final outcome = await write(context.read<SettingsService>());
      if (!mounted) return;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        setState(() => _writeError = failureMessage);
      }
    } catch (_) {
      if (mounted) setState(() => _writeError = failureMessage);
    } finally {
      if (mounted) {
        setState(() {
          _writing = false;
          _musicVolumeDraft = null;
          _notificationVolumeDraft = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final musicVolume = _musicVolumeDraft ?? settings.musicVolume;
    final notificationVolume =
        _notificationVolumeDraft ?? settings.notificationVolume;
    final slidersEnabled = settings.soundEnabled && !_writing;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: SettingsGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              toggleKey: const Key('sound_enabled_toggle'),
              label: 'Enable sound',
              description: 'Mute or unmute all ELIXR audio.',
              checked: settings.soundEnabled,
              onChanged: _writing
                  ? null
                  : (value) => _save(
                      write: (settings) => settings.setSoundEnabled(value),
                      failureMessage:
                          'Could not save sound preference. Try again.',
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Music volume',
              style: AppTheme.body.copyWith(
                fontSize: 14,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Controls background music across ELIXR.',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Slider(
              key: const Key('music_volume_slider'),
              value: musicVolume,
              min: 0.0,
              max: 1.0,
              label: '${(musicVolume * 100).round()}%',
              onChanged: !slidersEnabled
                  ? null
                  : (value) => setState(() => _musicVolumeDraft = value),
              onChangeEnd: !slidersEnabled
                  ? null
                  : (value) => _save(
                      write: (settings) => settings.setMusicVolume(value),
                      failureMessage: 'Could not save music volume. Try again.',
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Notification volume',
              style: AppTheme.body.copyWith(
                fontSize: 14,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Controls notification, chat, toast, and incoming alert sounds.',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Slider(
              key: const Key('notification_volume_slider'),
              value: notificationVolume,
              min: 0.0,
              max: 1.0,
              label: '${(notificationVolume * 100).round()}%',
              onChanged: !slidersEnabled
                  ? null
                  : (value) => setState(() => _notificationVolumeDraft = value),
              onChangeEnd: !slidersEnabled
                  ? null
                  : (value) => _save(
                      write: (settings) =>
                          settings.setNotificationVolume(value),
                      failureMessage:
                          'Could not save notification volume. Try again.',
                    ),
            ),
            if (_writeError != null)
              SettingsStatusBanner(message: _writeError!),
          ],
        ),
      ),
    );
  }
}
