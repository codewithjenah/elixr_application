import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../../data/models/coaching_verdict.dart';
import '../../data/models/practice_feedback.dart';
import '../theme/app_theme.dart';

/// The shared, trainee-facing presentation contract for live coaching.
///
/// Keep the label and icon here so a camera overlay cannot make an
/// unavailable observation look like a technique result merely by choosing a
/// different visual treatment.
class CoachingVerdictPresentation {
  const CoachingVerdictPresentation._({
    required this.verdict,
    required this.observationTip,
  });

  factory CoachingVerdictPresentation.fromFeedback(PracticeFeedback feedback) {
    return CoachingVerdictPresentation._(
      verdict: feedback.coachingVerdict,
      observationTip: _observationTipFor(feedback),
    );
  }

  factory CoachingVerdictPresentation.forVerdict(CoachingVerdict verdict) {
    return CoachingVerdictPresentation._(
      verdict: verdict,
      observationTip: verdict == CoachingVerdict.uncertain
          ? 'Hold position briefly and remain clearly visible while ELIXR observes again.'
          : null,
    );
  }

  final CoachingVerdict verdict;
  final String? observationTip;

  String get label => verdict.displayLabel;

  IconData get icon => coachingVerdictIcon(verdict);

  Color tone(BuildContext context, {required String feedbackType}) {
    final colors = context.elixColors;
    return switch (verdict) {
      CoachingVerdict.correct => colors.success,
      CoachingVerdict.uncertain => colors.textSecondary,
      CoachingVerdict.wrong =>
        feedbackType == 'error' ? colors.error : colors.warning,
    };
  }

  Color surface(BuildContext context) => context.elixColors.surfaceTinted;

  Color border(BuildContext context, {required String feedbackType}) =>
      context.isHighContrast
      ? context.elixColors.borderStrong
      : tone(context, feedbackType: feedbackType).withValues(alpha: 0.55);

  String semanticsLabel(String message) {
    final parts = <String>[label, message];
    if (observationTip != null) parts.add(observationTip!);
    return parts.where((part) => part.trim().isNotEmpty).join('. ');
  }

  static String? _observationTipFor(PracticeFeedback feedback) {
    if (feedback.coachingVerdict != CoachingVerdict.uncertain) return null;

    // The backend message is already the best contextual instruction when it
    // tells the trainee how to improve the observation. Do not repeat it.
    final message = feedback.feedback.toLowerCase();
    if (message.contains('visible') ||
        message.contains('in frame') ||
        message.contains('hold position')) {
      return null;
    }

    final code = feedback.feedbackCode?.toLowerCase() ?? '';
    final category = feedback.feedbackCategory?.toLowerCase();
    if (category == 'environment' ||
        code.contains('prop') ||
        code.contains('bottle') ||
        code.contains('shaker')) {
      return 'Keep the selected bottle or shaker clearly visible in frame.';
    }
    if (category == 'visibility' ||
        code.contains('hand') ||
        code.contains('shoulder') ||
        code.contains('body')) {
      return 'Keep your hands, prop, and upper body clearly visible.';
    }
    return 'Hold position briefly and remain clearly visible while ELIXR observes again.';
  }
}

Color coachingVerdictColor(
  CoachingVerdict verdict, {
  String feedbackType = 'warning',
}) {
  switch (verdict) {
    case CoachingVerdict.correct:
      return AppColors.success;
    case CoachingVerdict.uncertain:
      return AppColors.textSecondary;
    case CoachingVerdict.wrong:
      switch (feedbackType) {
        case 'error':
          return AppColors.error;
        default:
          return AppColors.warning;
      }
  }
}

IconData coachingVerdictIcon(CoachingVerdict verdict) {
  switch (verdict) {
    case CoachingVerdict.correct:
      return FluentIcons.status_circle_checkmark;
    case CoachingVerdict.uncertain:
      return FluentIcons.info_solid;
    case CoachingVerdict.wrong:
      return FluentIcons.warning;
  }
}
