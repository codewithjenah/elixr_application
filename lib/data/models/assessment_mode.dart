/// How an assignment or Teacher-created movement is assessed.
enum AssessmentMode {
  officialGuided('official_guided'),
  teacherReviewed('teacher_reviewed'),
  templateScored('template_scored');

  const AssessmentMode(this.wireValue);

  final String wireValue;

  static AssessmentMode? tryParse(String? value) {
    if (value == null) return null;
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return null;
  }

  String get displayLabel => switch (this) {
    AssessmentMode.officialGuided => 'Official ELIXR guided assessment',
    AssessmentMode.teacherReviewed => 'Teacher reviewed — no automatic score',
    AssessmentMode.templateScored => 'Template scored',
  };
}
