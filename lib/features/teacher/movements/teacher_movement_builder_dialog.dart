import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/teacher_reviewed_movement_spec.dart';
import '../../../data/models/training_prop.dart';
import 'teacher_movement_builder_draft.dart';

typedef TeacherReviewedSaveCallback =
    Future<void> Function({
      required String title,
      required String instructions,
      required TrainingProp requiredProp,
      String? safetyGuidance,
    });

/// Builder for the only writable Teacher-created assessment mode.
class TeacherMovementBuilderDialog extends StatefulWidget {
  const TeacherMovementBuilderDialog({
    super.key,
    required this.onCreateTeacherReviewed,
    this.existing,
    this.existingRevision,
    this.onEditTeacherReviewed,
  });

  final TeacherMovement? existing;
  final TeacherMovementRevision? existingRevision;
  final TeacherReviewedSaveCallback onCreateTeacherReviewed;
  final TeacherReviewedSaveCallback? onEditTeacherReviewed;

  @override
  State<TeacherMovementBuilderDialog> createState() =>
      _TeacherMovementBuilderDialogState();
}

class _TeacherMovementBuilderDialogState
    extends State<TeacherMovementBuilderDialog> {
  late final TeacherMovementBuilderDraft _draft;
  late final TextEditingController _title;
  late final TextEditingController _instructions;
  late final TextEditingController _safety;
  String? _validationMessage;

  bool get _isEditing => widget.existing != null;
  bool get _isRetiredTemplate =>
      widget.existingRevision?.isRetiredTemplate == true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final revision = widget.existingRevision;
    _draft = existing == null
        ? TeacherMovementBuilderDraft()
        : TeacherMovementBuilderDraft.editingExisting(
            title: existing.title,
            instructions: revision?.spec.instructions ?? '',
            requiredProp: revision?.spec.requiredProp ?? TrainingProp.bottle,
            safetyGuidance: revision?.spec.safetyGuidance,
          );
    _title = TextEditingController(text: _draft.title);
    _instructions = TextEditingController(text: _draft.instructions);
    _safety = TextEditingController(text: _draft.safetyGuidance);
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _safety.dispose();
    super.dispose();
  }

  void _syncDraftText() {
    _draft.title = _title.text;
    _draft.instructions = _instructions.text;
    _draft.safetyGuidance = _safety.text;
  }

  Future<void> _save() async {
    if (_isRetiredTemplate) return;
    _syncDraftText();
    final titleError = TeacherReviewedMovementSpec.validateTitle(_draft.title);
    final instructionsError = TeacherReviewedMovementSpec.validateInstructions(
      _draft.instructions,
    );
    final safetyError = TeacherReviewedMovementSpec.validateSafetyGuidance(
      _draft.safetyGuidance,
    );
    if (titleError != null ||
        instructionsError != null ||
        safetyError != null) {
      setState(() {
        _validationMessage = titleError ?? instructionsError ?? safetyError;
      });
      return;
    }
    if (_isEditing) {
      await widget.onEditTeacherReviewed?.call(
        title: _draft.title,
        instructions: _draft.instructions,
        requiredProp: _draft.requiredProp,
        safetyGuidance: _draft.safetyGuidance,
      );
    } else {
      await widget.onCreateTeacherReviewed(
        title: _draft.title,
        instructions: _draft.instructions,
        requiredProp: _draft.requiredProp,
        safetyGuidance: _draft.safetyGuidance,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = !_isRetiredTemplate;
    return ContentDialog(
      title: Text(_isEditing ? 'Edit movement' : 'Create movement'),
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoBar(
              title: Text(
                _isRetiredTemplate
                    ? 'Historical template scoring'
                    : 'Teacher reviewed',
              ),
              content: Text(
                _isRetiredTemplate
                    ? 'Automatic template assessment has been retired. '
                          'This historical movement is read-only; previous scores '
                          'remain available in classroom history.'
                    : 'The trainee submits a recording and the teacher reviews '
                          'it. No automatic ELIXR score is produced.',
              ),
              severity: _isRetiredTemplate
                  ? InfoBarSeverity.warning
                  : InfoBarSeverity.info,
            ),
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Title',
              child: TextBox(
                key: const ValueKey('builder-title'),
                controller: _title,
                enabled: fieldsEnabled,
                placeholder: 'Movement title',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Instructions',
              child: TextBox(
                key: const ValueKey('builder-instructions'),
                controller: _instructions,
                enabled: fieldsEnabled,
                maxLines: 6,
                placeholder: 'What the trainee should practice',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Required prop',
              child: ComboBox<TrainingProp>(
                value: _draft.requiredProp,
                items: [
                  for (final value in TrainingProp.values)
                    ComboBoxItem(value: value, child: Text(value.displayLabel)),
                ],
                onChanged: fieldsEnabled
                    ? (value) {
                        if (value == null) return;
                        setState(() => _draft.requiredProp = value);
                      }
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Safety guidance (optional)',
              child: TextBox(
                key: const ValueKey('builder-safety'),
                controller: _safety,
                enabled: fieldsEnabled,
                maxLines: 3,
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBar(
                title: const Text('Check the movement details'),
                content: Text(_validationMessage!),
                severity: InfoBarSeverity.warning,
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!_isRetiredTemplate)
          ElixPrimaryButton(
            key: const ValueKey('teacher-reviewed-save'),
            label: _isEditing ? 'Save revision' : 'Create',
            expanded: false,
            dense: true,
            onPressed: widget.onEditTeacherReviewed == null && _isEditing
                ? null
                : _save,
          ),
      ],
    );
  }
}
