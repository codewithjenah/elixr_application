import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_spacing.dart';

import '../../data/models/custom_movement.dart';
import '../../data/models/movement_template.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/custom_movement_repository.dart';
import 'custom_reference_recorder_dialog.dart';

typedef CustomReferenceRecorder =
    Future<MovementTemplate?> Function(
      BuildContext context,
      String difficulty,
      TrainingProp prop,
    );

const _rotationNotLearnedMessage =
    'Visible bottle rotation was not learned from these references. Re-record with orange tape on the top and yellow tape on the base visible through the turn. Hidden or extremely fast turns may remain uncertain.';

class CustomMovementBuilderDialog extends StatefulWidget {
  const CustomMovementBuilderDialog({
    super.key,
    required this.ownerUid,
    required this.ownerRole,
    required this.repository,
    this.existing,
    this.existingRevision,
    this.referenceRecorder,
  });

  final String ownerUid;
  final CustomMovementOwnerRole ownerRole;
  final CustomMovementRepository repository;
  final CustomMovement? existing;
  final CustomMovementRevision? existingRevision;
  final CustomReferenceRecorder? referenceRecorder;

  static Future<CustomMovement?> show(
    BuildContext context, {
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required CustomMovementRepository repository,
    CustomMovement? existing,
    CustomMovementRevision? existingRevision,
  }) => showDialog<CustomMovement>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CustomMovementBuilderDialog(
      ownerUid: ownerUid,
      ownerRole: ownerRole,
      repository: repository,
      existing: existing,
      existingRevision: existingRevision,
    ),
  );

  @override
  State<CustomMovementBuilderDialog> createState() =>
      _CustomMovementBuilderDialogState();
}

class _CustomMovementBuilderDialogState
    extends State<CustomMovementBuilderDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late String _difficulty;
  late TrainingProp _prop;
  MovementTemplate? _template;
  bool _requireVisibleBottleRotation = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _difficulty = existing?.difficulty ?? 'Easy';
    _prop = CustomMovement.supportedProps.contains(existing?.propType)
        ? existing!.propType
        : TrainingProp.bottle;
    _template = widget.existingRevision?.template;
    _requireVisibleBottleRotation =
        _prop == TrainingProp.bottle && _template?.requiresRotation == true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _recordReferences() async {
    final template = await (widget.referenceRecorder == null
        ? CustomReferenceRecorderDialog.show(
            context,
            difficulty: _difficulty,
            prop: _prop,
          )
        : widget.referenceRecorder!(context, _difficulty, _prop));
    if (template != null && mounted) {
      setState(() {
        if (_requireVisibleBottleRotation && !template.requiresRotation) {
          _template = null;
          _error = _rotationNotLearnedMessage;
        } else {
          _template = template;
          _error = null;
        }
      });
    }
  }

  bool get _assessmentReady =>
      _template?.isReady == true &&
      (!_requireVisibleBottleRotation || _template?.requiresRotation == true);

  Future<void> _save() async {
    final template = _template;
    final metadataError = CustomMovement.validateMetadata(
      name: _name.text,
      description: _description.text,
      difficulty: _difficulty,
    );
    if (metadataError != null || template == null || !_assessmentReady) {
      setState(() {
        _error =
            metadataError ??
            (_requireVisibleBottleRotation && template?.requiresRotation != true
                ? _rotationNotLearnedMessage
                : 'Record three valid references before saving.');
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.existing == null
          ? await widget.repository.createMovement(
              ownerUid: widget.ownerUid,
              ownerRole: widget.ownerRole,
              name: _name.text,
              description: _description.text,
              difficulty: _difficulty,
              propType: _prop,
              template: template,
            )
          : await widget.repository.publishRevision(
              current: widget.existing!,
              name: _name.text,
              description: _description.text,
              difficulty: _difficulty,
              propType: _prop,
              template: template,
            );
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the movement. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _surface(BuildContext context, Widget child) => Container(
    padding: const EdgeInsets.all(AppSpacing.mdPlus),
    decoration: BoxDecoration(
      color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: FluentTheme.of(context).resources.cardStrokeColorDefault,
      ),
    ),
    child: child,
  );

  Widget _details(BuildContext context) => _surface(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Movement details',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Name and configure what ELIXR will assess.'),
        const SizedBox(height: AppSpacing.md),
        const Text('Movement name'),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: const ValueKey('custom-movement-name'),
          controller: _name,
          enabled: !_busy,
          placeholder: 'Movement name',
          maxLength: CustomMovement.nameMaxLength,
        ),
        const SizedBox(height: AppSpacing.smPlus),
        const Text('Description'),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: const ValueKey('custom-movement-description'),
          controller: _description,
          enabled: !_busy,
          placeholder: 'Describe the movement',
          minLines: 2,
          maxLines: 3,
          maxLength: CustomMovement.descriptionMaxLength,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Difficulty'),
                  const SizedBox(height: AppSpacing.xs),
                  ComboBox<String>(
                    key: const ValueKey('custom-movement-difficulty'),
                    value: _difficulty,
                    isExpanded: true,
                    items: CustomMovement.allowedDifficulties
                        .map(
                          (value) =>
                              ComboBoxItem(value: value, child: Text(value)),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _difficulty = value!),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.smPlus),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Prop'),
                  const SizedBox(height: AppSpacing.xs),
                  ComboBox<TrainingProp>(
                    key: const ValueKey('custom-movement-prop'),
                    value: _prop,
                    isExpanded: true,
                    items: CustomMovement.supportedProps
                        .map(
                          (value) => ComboBoxItem(
                            value: value,
                            child: Text(value.displayLabel),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            if (value == null || value == _prop) return;
                            _prop = value;
                            _template = null;
                            if (value != TrainingProp.bottle) {
                              _requireVisibleBottleRotation = false;
                            }
                            _error = null;
                          }),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_prop == TrainingProp.bottle) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ToggleSwitch(
                key: const ValueKey('custom-movement-require-rotation'),
                checked: _requireVisibleBottleRotation,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _requireVisibleBottleRotation = value;
                        _error = null;
                      }),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('Require visible bottle rotation')),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Use when a visible turn is essential. Keep orange tape on the top and yellow tape on the base visible through the turn.',
          ),
        ],
      ],
    ),
  );

  Widget _references(BuildContext context, bool ready) => _surface(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Reference demonstrations',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Record three complete demonstrations to build the assessment template.',
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: List.generate(
            MovementTemplate.minimumReferences,
            (index) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 2 ? 0 : AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.smPlus,
                  ),
                  decoration: BoxDecoration(
                    color: ready
                        ? Colors.green.withValues(alpha: 0.12)
                        : FluentTheme.of(
                            context,
                          ).resources.cardBackgroundFillColorDefault,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: FluentTheme.of(
                        context,
                      ).resources.cardStrokeColorDefault,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        ready ? FluentIcons.completed : FluentIcons.circle_ring,
                        size: 18,
                        color: ready ? Colors.green : null,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Reference ${index + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          key: const ValueKey('custom-movement-record-references'),
          onPressed: _busy ? null : _recordReferences,
          child: Text(ready ? 'Re-record References' : 'Record References'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          ready
              ? 'Automatic assessment ready'
              : _requireVisibleBottleRotation
              ? 'Visible bottle rotation needed'
              : 'Automatic assessment needs 3 references',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          ready
              ? _template?.requiresRotation == true
                    ? 'This template learned visible bottle rotation from orange top and yellow base markers. Fast or hidden turns may remain uncertain.'
                    : _prop == TrainingProp.bottle
                    ? 'Bottle path, body and hands can be assessed. Rotation is learned when orange top and yellow base markers stay visible through consistent turns in all three references.'
                    : 'Prop path, body and hands can be assessed.'
              : _requireVisibleBottleRotation
              ? 'Keep the orange top and yellow base markers visible throughout each turn in all three references.'
              : 'Record all three valid references before saving.',
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBar(
            title: Text(
              _error == _rotationNotLearnedMessage
                  ? 'Rotation not learned'
                  : 'Could not save',
            ),
            content: Text(_error!),
            severity: InfoBarSeverity.error,
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ready = _assessmentReady;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 64).clamp(0.0, 1060.0);
    final height = (size.height - 96).clamp(0.0, 720.0);
    return ContentDialog(
      constraints: BoxConstraints(maxWidth: width, maxHeight: height),
      title: Text(
        widget.existing == null ? 'Create Movement' : 'Edit Movement',
      ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final children = <Widget>[
            _details(context),
            _references(context, ready),
          ];
          if (compact) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  children.first,
                  const SizedBox(height: AppSpacing.md),
                  children.last,
                ],
              ),
            );
          }
          return SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: children.first),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 5, child: children.last),
              ],
            ),
          );
        },
      ),
      actions: [
        Button(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('custom-movement-save'),
          onPressed: _busy || !ready ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
