import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/widgets/coaching_verdict_style.dart';
import 'package:elixr_application/data/models/coaching_verdict.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/widgets/training_status_row.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _feedback({
  String feedbackType = 'warning',
  String postureStatus = 'unstable',
  String? feedbackCode,
  String? feedbackCategory,
  String? errorCode,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Shoulder Stall',
    feedback: 'coaching',
    feedbackType: feedbackType,
    postureStatus: postureStatus,
    feedbackCode: feedbackCode,
    feedbackCategory: feedbackCategory,
    errorCode: errorCode,
  );
}

void main() {
  group('PracticeFeedback.coachingVerdict', () {
    test('unknown posture is uncertain regardless of warning urgency', () {
      final feedback = _feedback(
        feedbackType: 'warning',
        postureStatus: 'unknown',
        feedbackCode: 'shoulders_not_visible',
        feedbackCategory: 'visibility',
      );
      expect(feedback.coachingVerdict, CoachingVerdict.uncertain);
    });

    test('missing bottle error plus unknown is uncertain, not wrong', () {
      final feedback = _feedback(
        feedbackType: 'error',
        postureStatus: 'unknown',
        feedbackCode: 'prop_not_detected',
        feedbackCategory: 'environment',
      );
      expect(feedback.coachingVerdict, CoachingVerdict.uncertain);
    });

    test('positive and stable is correct', () {
      final feedback = _feedback(
        feedbackType: 'positive',
        postureStatus: 'stable',
        feedbackCode: 'shoulder_stall_locked',
        feedbackCategory: 'technique',
      );
      expect(feedback.coachingVerdict, CoachingVerdict.correct);
    });

    test('unstable is wrong even if leftover category is still visibility', () {
      final feedback = _feedback(
        feedbackType: 'warning',
        postureStatus: 'unstable',
        feedbackCode: 'hand_not_supporting_shaker',
        feedbackCategory: 'visibility',
      );
      expect(feedback.coachingVerdict, CoachingVerdict.wrong);
    });

    test('evaluable far-hand support fail is wrong', () {
      final feedback = _feedback(
        feedbackType: 'warning',
        postureStatus: 'unstable',
        feedbackCode: 'hand_not_supporting_shaker',
        feedbackCategory: 'technique',
      );
      expect(feedback.coachingVerdict, CoachingVerdict.wrong);
    });

    test('fatal session error is not the uncertain coaching state', () {
      final feedback = _feedback(
        feedbackType: 'error',
        postureStatus: 'unknown',
        errorCode: 'camera_unavailable',
      );
      expect(feedback.isSessionFatal, isTrue);
      expect(feedback.coachingVerdict, isNot(CoachingVerdict.uncertain));
    });
  });

  group('coaching verdict style', () {
    test('uncertain uses a neutral info color, not warning or error', () {
      final color = coachingVerdictColor(CoachingVerdict.uncertain);
      expect(color, AppColors.textSecondary);
      expect(color, isNot(AppColors.warning));
      expect(color, isNot(AppColors.error));
    });

    test('correct uses success and wrong keeps warning/error urgency', () {
      expect(coachingVerdictColor(CoachingVerdict.correct), AppColors.success);
      expect(
        coachingVerdictColor(CoachingVerdict.wrong, feedbackType: 'warning'),
        AppColors.warning,
      );
      expect(
        coachingVerdictColor(CoachingVerdict.wrong, feedbackType: 'error'),
        AppColors.error,
      );
    });
  });

  group('postureDisplayLabel', () {
    test('unknown is shown as cannot determine', () {
      expect(postureDisplayLabel('unknown'), "Can't determine");
    });

    test('stable and unstable labels stay posture-specific', () {
      expect(postureDisplayLabel('stable'), 'Posture stable');
      expect(postureDisplayLabel('unstable'), 'Posture unstable');
    });
  });
}
