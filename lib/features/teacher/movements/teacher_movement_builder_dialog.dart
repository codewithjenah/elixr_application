import 'dart:math' as math;

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
    final maxDialogHeight = math.max(
      1.0,
      MediaQuery.sizeOf(context).height - (AppSpacing.lg * 2),
    );
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
          maxWidth: 800,
          maxHeight: maxDialogHeight,
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
              _FormSection(
                icon: FluentIcons.edit,
                title: 'Movement details',
                description: 'Name the movement and its practice steps.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BuilderField(
                      label: 'Title',
                      helperText: 'Use a short, recognizable movement name.',
                      showHelper: false,
                      child: TextBox(
                        key: const ValueKey('builder-title'),
                        controller: _title,
                        enabled: fieldsEnabled,
                        autofocus: fieldsEnabled,
                        placeholder: 'Movement title',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _BuilderField(
                      label: 'Instructions',
                      helperText:
                          'Describe what the trainee should practice and submit.',
                      child: TextBox(
                        key: const ValueKey('builder-instructions'),
                        controller: _instructions,
                        enabled: fieldsEnabled,
                        minLines: 3,
                        maxLines: 3,
                        placeholder: 'Enter step-by-step practice guidance',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final practiceSetup = _FormSection(
                    icon: FluentIcons.product_variant,
                    title: 'Practice setup',
                    description:
                        'Choose the prop trainees need before recording.',
                    compact: true,
                    child: _BuilderField(
                      label: 'Required prop',
                      helperText: 'Required before recording begins.',
                      child: SizedBox(
                        width: double.infinity,
                        child: ComboBox<TrainingProp>(
                          value: _draft.requiredProp,
                          isExpanded: true,
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
                  );
                  final safetyGuidance = _FormSection(
                    icon: FluentIcons.shield,
                    title: 'Safety guidance',
                    description: 'Optional advice for a safer practice space.',
                    optional: true,
                    compact: true,
                    child: _BuilderField(
                      label: 'Guidance for trainees',
                      helperText: 'Add clearance or handling reminders.',
                      child: TextBox(
                        key: const ValueKey('builder-safety'),
                        controller: _safety,
                        enabled: fieldsEnabled,
                        minLines: 3,
                        maxLines: 3,
                        placeholder: 'Example: Keep the practice area clear',
                      ),
                    ),
                  );

                  if (constraints.maxWidth >= 620) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: practiceSetup),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(child: safetyGuidance),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      practiceSetup,
                      const SizedBox(height: AppSpacing.lg),
                      safetyGuidance,
                    ],
                  );
                },
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
    if (isRetiredTemplate) {
      final tone = context.elixColors.warning;
      return ElixPanelCard(
        accent: tone,
        showAccentBar: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _ReviewNoticeContent(tone: tone),
      );
    }

    final tone = context.elixColors.brandSecondary;
    return Semantics(
      label: 'Teacher reviewed. No automatic ELIXR score is produced.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.isHighContrast
              ? context.elixCardSurface
              : tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : tone.withValues(alpha: 0.22),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.education,
              size: 15,
              color: context.isHighContrast ? context.elixTextPrimary : tone,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Teacher reviewed',
              style: AppTheme.caption.copyWith(
                color: context.elixTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'No automatic ELIXR score',
                textAlign: TextAlign.end,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewNoticeContent extends StatelessWidget {
  const _ReviewNoticeContent({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FluentIcons.warning,
          size: 18,
          color: context.isHighContrast ? context.elixTextPrimary : tone,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Historical template scoring',
                style: AppTheme.label(color: context.elixTextPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Automatic template assessment has been retired. '
                'This historical movement is read-only; previous scores '
                'remain available in classroom history.',
                style: AppTheme.supporting(color: context.elixTextSecondary),
              ),
            ],
          ),
        ),
      ],
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

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.optional = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final bool optional;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.isHighContrast
                ? context.elixBorder
                : context.elixBorder.withValues(alpha: 0.7),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 16,
                color: context.isHighContrast
                    ? context.elixTextPrimary
                    : context.elixColors.brandPrimary,
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
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
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
    this.showHelper = true,
  });

  final String label;
  final String helperText;
  final Widget child;
  final bool showHelper;

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
        if (showHelper) ...[
          ExcludeSemantics(
            child: Text(
              helperText,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else
          const SizedBox(height: AppSpacing.xs),
        MergeSemantics(
          child: Semantics(label: label, hint: helperText, child: child),
        ),
      ],
    );
  }
}
