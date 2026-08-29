import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../services/settings_service.dart';
import '../../settings/widgets/practice_preferences_controller.dart';
import '../../settings/widgets/practice_preferences_editor.dart';
import '../../settings/widgets/settings_components.dart';

/// "Build Your Set" dialog: Live Practice shortcut over the shared Practice
/// preferences controller and editor.
///
/// Purely a settings editor — saving never scores, locks, or gates the
/// underlying freeform session.
class MovementSetlistDialog {
  const MovementSetlistDialog._();

  /// Shows the dialog. Resolves to `true` when the user saved changes
  /// (`saved` or clean `unchanged`), `false`/`null` when dismissed without
  /// saving.
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
  late final PracticePreferencesController _controller;
  bool _closing = false;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _controller = PracticePreferencesController(
      context.read<SettingsService>(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestClose({required bool popResult}) async {
    if (_closing) return;
    _closing = true;
    try {
      if (_controller.isDirty) {
        final discard = await SettingsDiscardConfirm.show(
          context,
          message:
              'You have unsaved Live Practice edits. Discard them and close?',
        );
        if (!mounted) return;
        if (!discard) return;
        _controller.discard();
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop(popResult);
    } finally {
      _closing = false;
    }
  }

  Future<void> _save() async {
    if (_saving || !_controller.canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final outcome = await _controller.save();
      if (!mounted) return;
      switch (outcome) {
        case SettingsWriteOutcome.saved:
        case SettingsWriteOutcome.unchanged:
          Navigator.of(context, rootNavigator: true).pop(true);
        case SettingsWriteOutcome.writeFailed:
          setState(() {
            _saveError = 'Could not save Live Practice preferences. Try again.';
          });
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e.message?.toString() ?? e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _requestClose(popResult: false);
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
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
                PracticePreferencesEditor(controller: _controller),
                if (_saveError != null)
                  SettingsStatusBanner(message: _saveError!),
              ],
            ),
            actions: [
              Button(
                onPressed: _saving
                    ? null
                    : () => _requestClose(popResult: false),
                child: const Text('Cancel'),
              ),
              ElixPrimaryButton(
                label: 'Save',
                expanded: false,
                onPressed: _controller.canSave && !_saving ? _save : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
