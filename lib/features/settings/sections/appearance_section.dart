import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/settings_service.dart';
import '../widgets/settings_components.dart';

/// Appearance Settings: dark mode, text size, and high contrast.
class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  bool _writing = false;
  String? _writeError;

  static const _textScaleOptions = <(double, String)>[
    (1.0, 'Default'),
    (1.15, 'Large'),
    (1.3, 'Extra Large'),
  ];

  Future<void> _persist(Future<SettingsWriteOutcome> Function() write) async {
    if (_writing) return;
    setState(() {
      _writing = true;
      _writeError = null;
    });

    final outcome = await write();
    if (!mounted) return;

    setState(() {
      _writing = false;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _writeError = 'Could not save appearance preference. Try again.';
      }
    });
  }

  Future<void> _onDarkModeChanged(bool value) {
    return _persist(() => context.read<SettingsService>().setDarkMode(value));
  }

  Future<void> _onTextScaleChanged(double value) {
    return _persist(() => context.read<SettingsService>().setTextScale(value));
  }

  Future<void> _onHighContrastChanged(bool value) {
    return _persist(
      () => context.read<SettingsService>().setHighContrast(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

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
                  label: 'Dark mode',
                  description: 'Use a dark color scheme across the app.',
                  checked: settings.darkMode,
                  onChanged: _writing ? null : _onDarkModeChanged,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Text size',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scale text across the app for easier reading.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final option in _textScaleOptions) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: RadioButton(
                      checked: settings.textScale == option.$1,
                      onChanged: _writing
                          ? null
                          : (checked) {
                              if (checked) _onTextScaleChanged(option.$1);
                            },
                      content: Text(option.$2),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SettingsToggleRow(
                  label: 'High contrast',
                  description:
                      'Use stronger text and borders for better visibility.',
                  checked: settings.highContrast,
                  onChanged: _writing ? null : _onHighContrastChanged,
                ),
                if (_writeError != null)
                  SettingsStatusBanner(message: _writeError!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
