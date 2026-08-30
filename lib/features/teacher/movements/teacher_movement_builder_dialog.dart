import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_panel_card.dart';
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
  bool _saving = false;

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
    if (_isRetiredTemplate || _saving) return;
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
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
    try {
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = !_isRetiredTemplate && !_saving;
    final accent = _isRetiredTemplate
        ? context.elixColors.warning
        : context.elixColors.brandPrimary;

    return FocusTraversalGroup(
      child: Center(
        child: ElixDialog(
          title: _isEditing ? 'Edit movement' : 'Create movement',
          subtitle: _isRetiredTemplate
              ? 'Review the preserved details for this historical movement.'
              : _isEditing
              ? 'Publish a new teacher-reviewed revision for future assignments.'
              : 'Define a focused movement for trainees to record and submit.',
          icon: FluentIcons.learning_tools,
          iconColor: accent,
          headerAccentColor: accent,
          maxWidth: 640,
          maxHeight: 760,
          scrollableContent: true,
          uniformActionSize: const Size(132, 40),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewModeNotice(isRetiredTemplate: _isRetiredTemplate),
              if (_validationMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                _ValidationNotice(message: _validationMessage!),
              ],
              const SizedBox(height: AppSpacing.md),
              _BuilderSection(
                icon: FluentIcons.edit,
                title: 'Movement details',
                description:
                    'Give trainees a clear name and precise practice steps.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BuilderField(
                      label: 'Title',
                      helperText: 'Use a short, recognizable movement name.',
                      child: TextBox(
                        key: const ValueKey('builder-title'),
                        controller: _title,
                        enabled: fieldsEnabled,
                        autofocus: fieldsEnabled,
                        placeholder: 'Movement title',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _BuilderField(
                      label: 'Instructions',
                      helperText:
                          'Describe what the trainee should practice and submit.',
                      child: TextBox(
                        key: const ValueKey('builder-instructions'),
                        controller: _instructions,
                        enabled: fieldsEnabled,
                        minLines: 4,
                        maxLines: 6,
                        placeholder: 'Enter step-by-step practice guidance',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _BuilderSection(
                icon: FluentIcons.product_variant,
                title: 'Practice setup',
                description:
                    'Choose the prop trainees need before they begin recording.',
                child: _BuilderField(
                  label: 'Required prop',
                  helperText:
                      'This appears with the assignment preparation details.',
                  child: SizedBox(
                    width: double.infinity,
                    child: ComboBox<TrainingProp>(
                      value: _draft.requiredProp,
                      items: [
                        for (final value in TrainingProp.values)
                          ComboBoxItem(
                            value: value,
                            child: Text(value.displayLabel),
                          ),
                      ],
                      onChanged: fieldsEnabled
                          ? (value) {
                              if (value == null) return;
                              setState(() => _draft.requiredProp = value);
                            }
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _BuilderSection(
                icon: FluentIcons.shield,
                title: 'Safety guidance',
                description:
                    'Optional supporting advice for a safer practice space.',
                optional: true,
                child: _BuilderField(
                  label: 'Guidance for trainees',
                  helperText:
                      'Add setup, clearance, or handling reminders when useful.',
                  child: TextBox(
                    key: const ValueKey('builder-safety'),
                    controller: _safety,
                    enabled: fieldsEnabled,
                    minLines: 2,
                    maxLines: 3,
                    placeholder: 'Example: Keep the practice area clear',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Button(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(_isRetiredTemplate ? 'Close' : 'Cancel'),
            ),
            if (!_isRetiredTemplate)
              ElixPrimaryButton(
                key: const ValueKey('teacher-reviewed-save'),
                label: _isEditing ? 'Save revision' : 'Create',
                expanded: false,
                dense: true,
                isLoading: _saving,
                onPressed: widget.onEditTeacherReviewed == null && _isEditing
                    ? null
                    : _save,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewModeNotice extends StatelessWidget {
  const _ReviewModeNotice({required this.isRetiredTemplate});

  final bool isRetiredTemplate;

  @override
  Widget build(BuildContext context) {
    final tone = isRetiredTemplate
        ? context.elixColors.warning
        : context.elixColors.brandSecondary;
    return ElixPanelCard(
      accent: tone,
      showAccentBar: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRetiredTemplate ? FluentIcons.warning : FluentIcons.education,
            size: 18,
            color: context.isHighContrast ? context.elixTextPrimary : tone,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRetiredTemplate
                      ? 'Historical template scoring'
                      : 'Teacher reviewed',
                  style: AppTheme.label(color: context.elixTextPrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  isRetiredTemplate
                      ? 'Automatic template assessment has been retired. '
                            'This historical movement is read-only; previous '
                            'scores remain available in classroom history.'
                      : 'The trainee submits a recording and the teacher '
                            'reviews it. No automatic ELIXR score is produced.',
                  style: AppTheme.supporting(color: context.elixTextSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationNotice extends StatelessWidget {
  const _ValidationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = context.elixColors.warning;
    return Container(
      key: const ValueKey('builder-validation'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : tone.withValues(alpha: 0.35),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.warning, size: 16, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTheme.supporting(color: context.elixTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuilderSection extends StatelessWidget {
  const _BuilderSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.optional = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.isHighContrast
                      ? context.elixCardSurface
                      : context.elixColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: context.isHighContrast
                      ? Border.all(color: context.elixBorder, width: 2)
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 15,
                  color: context.isHighContrast
                      ? context.elixTextPrimary
                      : context.elixColors.brandPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTheme.label(
                              color: context.elixTextPrimary,
                            ),
                          ),
                        ),
                        if (optional) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'OPTIONAL',
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _BuilderField extends StatelessWidget {
  const _BuilderField({
    required this.label,
    required this.helperText,
    required this.child,
  });

  final String label;
  final String helperText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: AppTheme.label(color: context.elixTextPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Text(
            helperText,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        MergeSemantics(
          child: Semantics(label: label, hint: helperText, child: child),
        ),
      ],
    );
  }
}
