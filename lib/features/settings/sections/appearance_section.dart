import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../services/settings_service.dart';
import '../widgets/settings_components.dart';

/// Appearance Settings: dark mode with transactional persistence.
class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  bool _writing = false;
  String? _writeError;

  Future<void> _onDarkModeChanged(bool value) async {
    if (_writing) return;
    setState(() {
      _writing = true;
      _writeError = null;
    });

    final settings = context.read<SettingsService>();
    final outcome = await settings.setDarkMode(value);
    if (!mounted) return;

    setState(() {
      _writing = false;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _writeError = 'Could not save appearance preference. Try again.';
      }
    });
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
