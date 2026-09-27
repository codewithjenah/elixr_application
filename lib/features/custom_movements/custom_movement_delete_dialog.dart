import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../data/models/custom_movement.dart';
import '../../data/models/custom_movement_save_diagnostics.dart';
import '../../data/repositories/custom_movement_repository.dart';

/// Confirms and performs the archive-only owner delete of a custom movement
/// through [CustomMovementRepository.deleteOwnedMovement]. Immutable
/// revisions, results, and assignment snapshots are never destroyed.
///
/// Shared by the trainee My Movements library and the Teacher Activity
/// Library; each caller supplies its own copy and key prefix.
class CustomMovementDeleteDialog extends StatefulWidget {
  const CustomMovementDeleteDialog({
    super.key,
    required this.movement,
    required this.ownerUid,
    required this.repository,
    required this.message,
    required this.keyPrefix,
  });

  final CustomMovement movement;
  final String ownerUid;
  final CustomMovementRepository repository;
  final String message;
  final String keyPrefix;

  /// Returns true only after the repository confirmed the delete.
  static Future<bool> show(
    BuildContext context, {
    required CustomMovement movement,
    required String ownerUid,
    required CustomMovementRepository repository,
    required String message,
    required String keyPrefix,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomMovementDeleteDialog(
        movement: movement,
        ownerUid: ownerUid,
        repository: repository,
        message: message,
        keyPrefix: keyPrefix,
      ),
    );
    return result == true;
  }

  @override
  State<CustomMovementDeleteDialog> createState() =>
      _CustomMovementDeleteDialogState();
}

class _CustomMovementDeleteDialogState
    extends State<CustomMovementDeleteDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.repository.deleteOwnedMovement(
        movementId: widget.movement.id,
        ownerUid: widget.ownerUid,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(true);
    } on Object catch (error, stackTrace) {
      emitCustomMovementDeleteDiagnostic(error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = customMovementDeleteFailureMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElixDialog(
      title: 'Delete movement?',
      icon: FluentIcons.delete,
      iconColor: context.elixColors.error,
      headerAccentColor: context.elixColors.error,
      showCloseButton: !_deleting,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: const Text('Could not delete movement'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
          ],
        ],
      ),
      actions: [
        ElixPrimaryButton(
          key: ValueKey('${widget.keyPrefix}-cancel'),
          label: 'Cancel',
          expanded: false,
          variant: ElixButtonVariant.secondary,
          onPressed: _deleting
              ? null
              : () => Navigator.of(context, rootNavigator: true).pop(false),
        ),
        ElixPrimaryButton(
          key: ValueKey('${widget.keyPrefix}-confirm'),
          label: _deleting ? 'Deleting…' : 'Delete',
          expanded: false,
          isLoading: _deleting,
          variant: ElixButtonVariant.destructive,
          onPressed: _deleting ? null : _delete,
        ),
      ],
    );
  }
}
