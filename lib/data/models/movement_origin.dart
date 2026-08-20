enum MovementOrigin {
  officialElixr('official_elixr'),
  teacherCreated('teacher_created');

  const MovementOrigin(this.wireValue);

  final String wireValue;

  static MovementOrigin? tryParse(String? value) {
    if (value == null) return null;
    for (final origin in values) {
      if (origin.wireValue == value) return origin;
    }
    return null;
  }

  String get displayLabel => switch (this) {
    MovementOrigin.officialElixr => 'Official ELIXR',
    MovementOrigin.teacherCreated => 'Teacher-created',
  };
}
