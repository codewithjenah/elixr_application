import 'package:elixr_application/features/practice/widgets/training_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trainingPerformanceLabel', () {
    test('uses rubric performance-level thresholds', () {
      expect(trainingPerformanceLabel(0), 'Beginning');
      expect(trainingPerformanceLabel(3), 'Beginning');
      expect(trainingPerformanceLabel(4), 'Developing');
      expect(trainingPerformanceLabel(6), 'Developing');
      expect(trainingPerformanceLabel(7), 'Competent');
      expect(trainingPerformanceLabel(9), 'Competent');
      expect(trainingPerformanceLabel(10), 'Proficient');
      expect(trainingPerformanceLabel(11), 'Proficient');
      expect(trainingPerformanceLabel(12), 'Mastered');
    });

    test('clamps out-of-range totals instead of throwing', () {
      expect(trainingPerformanceLabel(-1), 'Beginning');
      expect(trainingPerformanceLabel(13), 'Mastered');
    });
  });

  group('trainingPerformanceFraction', () {
    test('null is 0', () {
      expect(trainingPerformanceFraction(null), 0.0);
    });

    test('is a fraction of 12 and clamps out-of-range totals', () {
      expect(trainingPerformanceFraction(0), 0.0);
      expect(trainingPerformanceFraction(6), 0.5);
      expect(trainingPerformanceFraction(12), 1.0);
      expect(trainingPerformanceFraction(-4), 0.0);
      expect(trainingPerformanceFraction(24), 1.0);
    });
  });
}
