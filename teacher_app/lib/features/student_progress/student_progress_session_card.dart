import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/material.dart';

import 'student_progress_formatters.dart';

class StudentProgressSessionCard extends StatefulWidget {
  const StudentProgressSessionCard({super.key, required this.session});
  final PublicProfileSession session;

  @override
  State<StudentProgressSessionCard> createState() =>
      _StudentProgressSessionCardState();
}

class _StudentProgressSessionCardState
    extends State<StudentProgressSessionCard> {
  bool _expanded = false;

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
                onPressed: () => setState(() => _expanded = !_expanded),
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
            ],
          ],
        ),
      ),
    );
  }
}
