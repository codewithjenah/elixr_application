import 'dart:typed_data';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'student_progress_formatters.dart';

class StudentProgressSessionCard extends StatefulWidget {
  const StudentProgressSessionCard({
    super.key,
    required this.session,
    this.traineeId = '',
    this.evidenceAllowed = false,
    this.evidenceRepository,
  });
  final PublicProfileSession session;
  final String traineeId;
  final bool evidenceAllowed;
  final TeacherEvidenceRepository? evidenceRepository;

  @override
  State<StudentProgressSessionCard> createState() =>
      _StudentProgressSessionCardState();
}

class _StudentProgressSessionCardState
    extends State<StudentProgressSessionCard> {
  bool _expanded = false;
  Uint8List? _evidence;
  bool _loadingEvidence = false;
  String? _evidenceError;

  @override
  void didUpdateWidget(covariant StudentProgressSessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.evidenceAllowed && oldWidget.evidenceAllowed) {
      _evidence = null;
      _evidenceError = 'Image permission was withdrawn.';
      _loadingEvidence = false;
    }
  }

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (!_expanded ||
        _evidence != null ||
        _loadingEvidence ||
        widget.session.evidenceAvailable != true ||
        !widget.evidenceAllowed) {
      return;
    }
    setState(() {
      _loadingEvidence = true;
      _evidenceError = null;
    });
    try {
      final bytes = await widget.evidenceRepository?.downloadEvidence(
        traineeId: widget.traineeId,
        sessionId: widget.session.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _evidence = bytes;
        if (bytes == null) {
          _evidenceError = 'Saved image is unavailable.';
        }
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _evidenceError = error.code == 'unauthorized'
            ? 'Image permission was withdrawn.'
            : error.code == 'object-not-found'
            ? 'Saved image is unavailable.'
            : 'Could not load the saved image.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _evidenceError = 'Could not load the saved image.');
      }
    } finally {
      if (mounted) setState(() => _loadingEvidence = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final rubric = session.rubric;
    final assessment = session.isRubricAssessed
        ? 'Assessment V2 · ${rubric!.total}/${RubricAssessment.maxTotalScore} · ${rubric.performanceLevel.label}'
        : 'Assessment V1 · Legacy · ${session.legacyScore}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.movementName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${session.difficulty} · ${formatSessionDate(context, session.createdAt)}',
            ),
            const SizedBox(height: 4),
            Text(
              '${formatPracticeDuration(session.durationSeconds)} · ${session.propType.displayLabel}',
            ),
            const SizedBox(height: 8),
            Text(assessment),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _toggle,
                child: Text(_expanded ? 'Hide details' : 'View details'),
              ),
            ),
            if (_expanded) ...[
              const Divider(),
              if (session.isRubricAssessed)
                for (final criterion in RubricCriterion.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${criterion.label}: ${rubric!.scoreFor(criterion)}/${RubricAssessment.maxCriterionScore}',
                    ),
                  )
              else
                const Text(
                  'Criterion-level rubric scores are unavailable for Assessment V1.',
                ),
              if (session.evidenceAvailable == true) ...[
                const SizedBox(height: 8),
                if (!widget.evidenceAllowed)
                  const Text('Saved image sharing is off for this Teacher.')
                else if (_loadingEvidence)
                  const LinearProgressIndicator()
                else if (_evidenceError != null)
                  Text(_evidenceError!)
                else if (_evidence != null)
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(
                          child: Image.memory(_evidence!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    child: Image.memory(
                      _evidence!,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
