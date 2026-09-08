import '../../data/models/movement.dart';

/// Canonical instructional content for an official ELIXR movement.
///
/// This is intentionally presentation-neutral: trainee lessons and the
/// teacher library both read it, while only the trainee lesson owns progress.
class MovementLesson {
  const MovementLesson({
    required this.objective,
    required this.framing,
    required this.steps,
    required this.successTarget,
    required this.commonMistake,
    this.safetyNote,
  });

  final String objective, framing, successTarget, commonMistake;
  final List<String> steps;
  final String? safetyNote;

  factory MovementLesson.forMovement(Movement movement) {
    final balance =
        movement.name.contains('Stall') || movement.name == 'Bottle in a tin';
    return MovementLesson(
      objective:
          'Learn a controlled ${movement.name} before you open the camera.',
      framing:
          'Place the camera so your hands, prop, and upper body are clearly visible.',
      steps: balance
          ? const [
              'Prepare a clear space and a safe practice prop.',
              'Start from a steady position.',
              'Move the prop to the named support point.',
              'Hold still while keeping the prop controlled.',
            ]
          : [
              'Prepare a clear space and a safe practice prop.',
              'Hold the prop in a relaxed starting position.',
              'Place your hand in the ${movement.name} position.',
              'Keep the prop controlled and hold the position.',
            ],
      successTarget: balance
          ? 'Hold the prop steadily at the correct support point.'
          : 'Show the grip clearly and keep it steady long enough for ELIXR to observe.',
      commonMistake: balance
          ? 'Rushing into the balance. Reset, lower the prop, and hold steady.'
          : 'Covering the grip with your hand. Turn the prop so the camera can see your fingers.',
      safetyNote: balance
          ? 'Use a safe practice prop and keep people and breakable items out of your practice area.'
          : null,
    );
  }
}
