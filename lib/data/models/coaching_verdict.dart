enum CoachingVerdict {
  correct,
  wrong,
  uncertain;

  String get displayLabel => switch (this) {
    CoachingVerdict.correct => 'Correct',
    CoachingVerdict.wrong => 'Wrong',
    CoachingVerdict.uncertain => "Can't determine",
  };
}

const nonEvaluableFeedbackCategories = {'visibility', 'environment', 'system'};
