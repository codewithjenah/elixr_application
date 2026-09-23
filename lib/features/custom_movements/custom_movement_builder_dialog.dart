import 'package:fluent_ui/fluent_ui.dart';

import '../../data/models/custom_movement.dart';
import '../../data/models/movement_template.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/custom_movement_repository.dart';
import 'custom_reference_recorder_dialog.dart';

class CustomMovementBuilderDialog extends StatefulWidget {
  const CustomMovementBuilderDialog({
    super.key,
    required this.ownerUid,
    required this.ownerRole,
    required this.repository,
    this.existing,
    this.existingRevision,
  });

  final String ownerUid;
  final CustomMovementOwnerRole ownerRole;
  final CustomMovementRepository repository;
  final CustomMovement? existing;
  final CustomMovementRevision? existingRevision;

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
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _recordReferences() async {
    final template = await CustomReferenceRecorderDialog.show(
      context,
      difficulty: _difficulty,
      prop: _prop,
    );
    if (template != null && mounted) {
      setState(() {
        _template = template;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final template = _template;
    final metadataError = CustomMovement.validateMetadata(
      name: _name.text,
      description: _description.text,
      difficulty: _difficulty,
    );
    if (metadataError != null || template == null || !template.isReady) {
      setState(() {
        _error =
            metadataError ?? 'Record three valid references before saving.';
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

  @override
  Widget build(BuildContext context) {
    final ready = _template?.isReady == true;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
      title: Text(
        widget.existing == null ? 'Create Movement' : 'Edit Movement',
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Movement details'),
            const SizedBox(height: 8),
            TextBox(
              key: const ValueKey('custom-movement-name'),
              controller: _name,
              enabled: !_busy,
              placeholder: 'Movement name',
              maxLength: CustomMovement.nameMaxLength,
            ),
            const SizedBox(height: 8),
            TextBox(
              key: const ValueKey('custom-movement-description'),
              controller: _description,
              enabled: !_busy,
              placeholder: 'Describe the movement',
              minLines: 3,
              maxLines: 5,
              maxLength: CustomMovement.descriptionMaxLength,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Difficulty'),
                      const SizedBox(height: 6),
                      ComboBox<String>(
                        key: const ValueKey('custom-movement-difficulty'),
                        value: _difficulty,
                        isExpanded: true,
                        items: CustomMovement.allowedDifficulties
                            .map(
                              (value) => ComboBoxItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _difficulty = value!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Prop'),
                      const SizedBox(height: 6),
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
                              }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Reference demonstrations',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 6),
            const Text(
              'Record three complete demonstrations. ELIXR will align them into one automatic assessment template.',
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(MovementTemplate.minimumReferences, (
                index,
              ) {
                final complete = ready;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: complete
                          ? Colors.green.withValues(alpha: 0.12)
                          : FluentTheme.of(
                              context,
                            ).resources.cardBackgroundFillColorDefault,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          complete
                              ? FluentIcons.accept
                              : FluentIcons.circle_ring,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text('${index + 1}${complete ? ' ✓' : ''}'),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Button(
              key: const ValueKey('custom-movement-record-references'),
              onPressed: _busy ? null : _recordReferences,
              child: Text(ready ? 'Re-record References' : 'Record Reference'),
            ),
            const SizedBox(height: 8),
            InfoBar(
              title: Text(
                ready
                    ? 'Automatic assessment ready'
                    : 'Automatic assessment needs 3 references',
              ),
              content: Text(
                _template?.requiresRotation == true
                    ? 'This template learned visible bottle rotation from top and base observations. Fast or hidden turns may remain uncertain.'
                    : 'Bottle path, body and hands can be assessed. Rotation is learned only when a validated bottle keypoint model is installed and all three references show consistent visible turns. Fully hidden behind-the-back depth cannot be confirmed by one camera.',
              ),
              severity: ready ? InfoBarSeverity.success : InfoBarSeverity.info,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              InfoBar(
                title: const Text('Could not save'),
                content: Text(_error!),
                severity: InfoBarSeverity.error,
              ),
            ],
          ],
        ),
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
