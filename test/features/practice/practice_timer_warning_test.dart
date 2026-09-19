import 'package:elixr_application/features/practice/practice_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timer warning is limited to a new active attempt at exactly ten', () {
    expect(
      shouldPlayPracticeTimerWarning(
        isTrainingActive: true,
        remainingSeconds: 10,
        lifecycleGeneration: 4,
        playedGeneration: null,
      ),
      isTrue,
    );
    expect(
      shouldPlayPracticeTimerWarning(
        isTrainingActive: true,
        remainingSeconds: 10,
        lifecycleGeneration: 4,
        playedGeneration: 4,
      ),
      isFalse,
    );
    expect(
      shouldPlayPracticeTimerWarning(
        isTrainingActive: true,
        remainingSeconds: 10,
        lifecycleGeneration: 5,
        playedGeneration: 4,
      ),
      isTrue,
    );
    expect(
      shouldPlayPracticeTimerWarning(
        isTrainingActive: false,
        remainingSeconds: 10,
        lifecycleGeneration: 5,
        playedGeneration: null,
      ),
      isFalse,
    );
    expect(
      shouldPlayPracticeTimerWarning(
        isTrainingActive: true,
        remainingSeconds: 9,
        lifecycleGeneration: 5,
        playedGeneration: null,
      ),
      isFalse,
    );
  });
}
