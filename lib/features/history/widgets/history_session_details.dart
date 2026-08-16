import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/feedback.dart' as models;
import '../../../data/models/rubric_assessment.dart';
import '../../../data/models/session.dart';
import '../../../data/repositories/session_evidence_repository.dart';
import '../history_format.dart';

class HistorySessionDetails extends StatelessWidget {
  const HistorySessionDetails({
    super.key,
    required this.session,
    required this.loading,
    required this.feedbacks,
    this.errorMessage,
  });

  final Session session;
  final bool loading;
  final List<models.Feedback>? feedbacks;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final created = session.createdAt != null
        ? DateTime.parse(session.createdAt!).toLocal()
        : null;
    final exactDate = created != null
        ? DateFormat.yMMMMd().add_jm().format(created)
        : 'Unknown date';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? context.elixBackground.withValues(alpha: 0.55)
            : context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _MetaItem(label: 'Date', value: exactDate),
              _MetaItem(
                label: 'Duration',
                value: formatTrainingDuration(session.durationSeconds),
              ),
              _MetaItem(label: 'Difficulty', value: session.difficulty),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _AssessmentBlock(session: session),
          const SizedBox(height: AppSpacing.md),
          _SessionEvidenceCard(session: session),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Session Feedback',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Loading feedback…',
                    style: AppTheme.bodySecondary.copyWith(
                      color: context.elixTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else if (errorMessage != null)
            Text(
              errorMessage!,
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
                fontSize: 13,
              ),
            )
          else if (feedbacks == null || feedbacks!.isEmpty)
            Text(
              'No feedback recorded',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
                fontSize: 13,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final feedback in feedbacks!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '•  ',
                          style: TextStyle(
                            color: context.elixTextSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            feedback.message,
                            style: AppTheme.bodySecondary.copyWith(
                              color: context.elixTextPrimary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SessionEvidenceCard extends StatefulWidget {
  const _SessionEvidenceCard({required this.session});
  final Session session;

  @override
  State<_SessionEvidenceCard> createState() => _SessionEvidenceCardState();
}

class _SessionEvidenceCardState extends State<_SessionEvidenceCard> {
  SessionEvidenceRepository? _repository;
  Future<Uint8List?>? _image;

  @override
  void didUpdateWidget(covariant _SessionEvidenceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.evidenceStoragePath !=
        widget.session.evidenceStoragePath) {
      _image = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.session.evidenceStoragePath;
    if (path == null || widget.session.evidenceKind != 'hold_confirmed') {
      return Text(
        'No confirmed movement image',
        style: AppTheme.bodySecondary.copyWith(
          color: context.elixTextSecondary,
          fontSize: 13,
        ),
      );
    }
    final repository = _repository ??= SessionEvidenceRepository();
    _image ??= repository.download(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirmed movement image',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: FutureBuilder<Uint8List?>(
            future: _image,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: ProgressRing());
              }
              final image = snapshot.data;
              if (snapshot.hasError || image == null) {
                return Button(
                  onPressed: () =>
                      setState(() => _image = repository.download(path)),
                  child: const Text('Image unavailable — Retry'),
                );
              }
              return GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => ContentDialog(
                    title: const Text('Confirmed movement image'),
                    content: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(-1, 1, 1),
                      child: Image.memory(image),
                    ),
                    actions: [
                      Button(
                        child: const Text('Close'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(-1, 1, 1),
                      child: Image.memory(image, fit: BoxFit.contain),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Assessment read-out: the four V2 criteria, or the legacy percentage.
class _AssessmentBlock extends StatelessWidget {
  const _AssessmentBlock({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final rubric = session.rubric;
    if (!session.isRubricAssessed || rubric == null) {
      final legacy = session.legacyScore;
      return Text(
        legacy == null ? 'No score recorded' : legacyScoreLabel(legacy),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.elixTextPrimary,
        ),
      );
    }

    final level = rubricPerformanceLevel(rubric.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            _MetaItem(label: 'Performance', value: level.label),
            _MetaItem(
              label: 'Rubric Total',
              value: rubricTotalLabel(rubric.total),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            for (final criterion in RubricCriterion.values)
              _MetaItem(
                label: criterion.label,
                value: '${rubric.scoreFor(criterion)} / 3',
              ),
          ],
        ),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.elixTextPrimary,
          ),
        ),
      ],
    );
  }
}
