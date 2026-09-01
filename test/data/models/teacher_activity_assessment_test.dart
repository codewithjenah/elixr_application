import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Teacher Activity readiness', () {
    test('supports camera-only hand and body visibility requirements', () {
      expect(const TeacherActivityReadinessSpec().isCameraOnly, isTrue);
      for (final hands in ActivityHandRequirement.values) {
        for (final body in ActivityBodyRequirement.values) {
          final value = TeacherActivityReadinessSpec(hands: hands, body: body);
          expect(
            TeacherActivityReadinessSpec.tryFrom(value.toMap())?.toMap(),
            value.toMap(),
          );
        }
      }
    });

    test('rejects unknown readiness keys and values', () {
      expect(
        TeacherActivityReadinessSpec.tryFrom({
          'hands': 'one_hand',
          'body': 'upper_body',
          'technique': true,
        }),
        isNull,
      );
      expect(
        TeacherActivityReadinessSpec.tryFrom({
          'hands': 'three_hands',
          'body': 'none',
        }),
        isNull,
      );
    });
  });

  group('rubrics and score presets', () {
    test('all built-ins scale deterministically to each preset', () {
      for (final template in TeacherActivityRubricTemplate.values.where(
        (value) => value != TeacherActivityRubricTemplate.custom,
      )) {
        for (final maximum in const [30, 50, 100]) {
          final first = TeacherActivityRubric.builtIn(template, maximum);
          final second = TeacherActivityRubric.builtIn(template, maximum);
          expect(first.isValid, isTrue);
          expect(first.criteria.length, inInclusiveRange(3, 5));
          expect(
            first.criteria.map((criterion) => criterion.maximumPoints),
            second.criteria.map((criterion) => criterion.maximumPoints),
          );
          expect(
            first.criteria.fold<int>(
              0,
              (sum, criterion) => sum + criterion.maximumPoints,
            ),
            maximum,
          );
        }
      }
    });

    test('custom rubric is valid only when 3-5 criteria total the maximum', () {
      TeacherActivityRubric custom(List<int> points) => TeacherActivityRubric(
        template: TeacherActivityRubricTemplate.custom,
        maximumScore: 30,
        criteria: [
          for (var i = 0; i < points.length; i++)
            TeacherActivityRubricCriterion(
              id: 'criterion_$i',
              label: 'Criterion $i',
              description: 'Visible grading evidence $i.',
              maximumPoints: points[i],
            ),
        ],
      );

      expect(custom([10, 10, 10]).isValid, isTrue);
      expect(custom([10, 10, 9]).isValid, isFalse);
      expect(custom([15, 15]).isValid, isFalse);
      expect(custom([6, 6, 6, 6, 6, 1]).isValid, isFalse);
    });
  });

  group('attempt and recording contracts', () {
    test('accepts finite 1-3 and Unlimited policies', () {
      for (final maximum in const [1, 2, 3]) {
        final policy = AssignmentAttemptPolicy.finite(maximum);
        expect(
          AssignmentAttemptPolicy.tryFrom(policy.toMap())?.maximumAttempts,
          maximum,
        );
      }
      expect(
        AssignmentAttemptPolicy.tryFrom(
          const AssignmentAttemptPolicy.unlimited().toMap(),
        )?.isUnlimited,
        isTrue,
      );
      expect(
        AssignmentAttemptPolicy.tryFrom({
          'type': 'finite',
          'maximum_attempts': 4,
        }),
        isNull,
      );
    });

    test('accepts only 15/30/45/60 second assessment durations', () {
      final rubric = TeacherActivityRubric.builtIn(
        TeacherActivityRubricTemplate.standardTechnique,
        50,
      );
      for (final duration in const [15, 30, 45, 60]) {
        expect(
          TeacherActivityAssessmentConfig(
            readiness: const TeacherActivityReadinessSpec(),
            rubric: rubric,
            recordingDurationSeconds: duration,
          ).isValid,
          isTrue,
        );
      }
      expect(
        TeacherActivityAssessmentConfig(
          readiness: const TeacherActivityReadinessSpec(),
          rubric: rubric,
          recordingDurationSeconds: 20,
        ).isValid,
        isFalse,
      );
    });

    test('demo metadata enforces private mp4 50 MiB/60 second bounds', () {
      final valid = {
        'storage_path': 'teacher_activity_demos/t/a/r/demo.mp4',
        'content_type': 'video/mp4',
        'size_bytes': 50 * 1024 * 1024,
        'duration_ms': 60000,
        'source': 'uploaded',
      };
      expect(TeacherActivityVideoMetadata.tryFrom(valid), isNotNull);
      expect(
        TeacherActivityVideoMetadata.tryFrom({
          ...valid,
          'size_bytes': 50 * 1024 * 1024 + 1,
        }),
        isNull,
      );
      expect(
        TeacherActivityVideoMetadata.tryFrom({...valid, 'duration_ms': 60001}),
        isNull,
      );
    });
  });
}
