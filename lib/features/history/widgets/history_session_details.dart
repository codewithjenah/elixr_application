import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/feedback.dart' as models;
import '../../../data/models/rubric_assessment.dart';
import '../../../data/models/session.dart';
import '../../../data/repositories/session_evidence_repository.dart';
import '../history_format.dart';

abstract final class _InspectorLayout {
  static const twoColumnBreakpoint = 720.0;
  static const stillWidth = 280.0;
  static const stillMaxHeightWide = 210.0;
  static const stillMaxHeightNarrow = 200.0;
  static const dialogMaxWidth = 760.0;
}

class HistorySessionDetails extends StatelessWidget {
  const HistorySessionDetails({
    super.key,
    required this.session,
    required this.loading,
    required this.feedbacks,
    this.errorMessage,
    this.loadEvidence,
  });

  final Session session;
  final bool loading;
  final List<models.Feedback>? feedbacks;
  final String? errorMessage;

  /// Test seam so widget tests can render the preview without Firebase Storage.
  final Future<Uint8List?> Function(String path)? loadEvidence;

  bool get _hasConfirmedStill =>
      session.evidenceStoragePath != null &&
      session.evidenceKind == 'hold_confirmed';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= _InspectorLayout.twoColumnBreakpoint &&
              _hasConfirmedStill;
          final still = _SessionEvidenceCard(
            session: session,
            maxWidth: wide ? _InspectorLayout.stillWidth : double.infinity,
            maxHeight: wide
                ? _InspectorLayout.stillMaxHeightWide
                : _InspectorLayout.stillMaxHeightNarrow,
            loadEvidence: loadEvidence,
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AssessmentBlock(session: session),
                      const SizedBox(height: AppSpacing.md),
                      _FeedbackBlock(
                        loading: loading,
                        feedbacks: feedbacks,
                        errorMessage: errorMessage,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: _InspectorLayout.stillWidth, child: still),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AssessmentBlock(session: session),
              const SizedBox(height: AppSpacing.md),
              still,
              const SizedBox(height: AppSpacing.md),
              _FeedbackBlock(
                loading: loading,
                feedbacks: feedbacks,
                errorMessage: errorMessage,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FeedbackBlock extends StatelessWidget {
  const _FeedbackBlock({
    required this.loading,
    required this.feedbacks,
    this.errorMessage,
  });

  final bool loading;
  final List<models.Feedback>? feedbacks;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    );
  }
}

class _SessionEvidenceCard extends StatefulWidget {
  const _SessionEvidenceCard({
    required this.session,
    required this.maxWidth,
    required this.maxHeight,
    this.loadEvidence,
  });

  final Session session;
  final double maxWidth;
  final double maxHeight;
  final Future<Uint8List?> Function(String path)? loadEvidence;

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
            widget.session.evidenceStoragePath ||
        oldWidget.loadEvidence != widget.loadEvidence) {
      _image = null;
    }
  }

  Future<Uint8List?> _download(String path) {
    final loader = widget.loadEvidence;
    if (loader != null) return loader(path);
    final repository = _repository ??= SessionEvidenceRepository();
    return repository.download(path);
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
    _image ??= _download(path);
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
        SizedBox(
          width: widget.maxWidth.isFinite ? widget.maxWidth : double.infinity,
          height: widget.maxHeight,
          child: FutureBuilder<Uint8List?>(
            future: _image,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return _StillFrame(child: const Center(child: ProgressRing()));
              }
              final image = snapshot.data;
              if (snapshot.hasError || image == null) {
                return _StillFrame(
                  child: Center(
                    child: Button(
                      onPressed: () => setState(() => _image = _download(path)),
                      child: const Text('Image unavailable — Retry'),
                    ),
                  ),
                );
              }
              return Tooltip(
                message: 'View confirmed frame',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openLightbox(context, image),
                  child: Semantics(
                    button: true,
                    label: 'View confirmed movement frame',
                    child: _StillFrame(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(-1, 1, 1),
                            child: Image.memory(image, fit: BoxFit.contain),
                          ),
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Color(0x8C000000),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    'Click to enlarge',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

  void _openLightbox(BuildContext context, Uint8List image) {
    showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        constraints: const BoxConstraints(
          maxWidth: _InspectorLayout.dialogMaxWidth,
        ),
        title: const Text('Confirmed movement image'),
        content: AspectRatio(
          aspectRatio: 4 / 3,
          child: ColoredBox(
            color: Colors.black,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              child: Image.memory(image, fit: BoxFit.contain),
            ),
          ),
        ),
        actions: [
          Button(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _StillFrame extends StatelessWidget {
  const _StillFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        key: const Key('history-evidence-preview'),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
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
    final levelColor = performanceLevelColor(level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Performance',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              level.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: levelColor,
              ),
            ),
            Text(
              '·',
              style: TextStyle(fontSize: 13, color: context.elixTextSecondary),
            ),
            Text(
              'Rubric Total',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              rubricTotalLabel(rubric.total),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final criterion in RubricCriterion.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _CriterionMeter(
              label: criterion.label,
              score: rubric.scoreFor(criterion),
              fillColor: levelColor,
            ),
          ),
      ],
    );
  }
}

class _CriterionMeter extends StatelessWidget {
  const _CriterionMeter({
    required this.label,
    required this.score,
    required this.fillColor,
  });

  final String label;
  final int score;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: i < score
                    ? fillColor
                    : context.elixBorder.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 36,
          child: Text(
            '$score / 3',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
