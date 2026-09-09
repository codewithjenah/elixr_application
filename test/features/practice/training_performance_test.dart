import 'package:elixr_application/features/practice/widgets/training_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trainingPerformanceLabel', () {
    test('uses rubric performance-level thresholds', () {
      expect(trainingPerformanceLabel(0), 'Getting Started');
      expect(trainingPerformanceLabel(3), 'Getting Started');
      expect(trainingPerformanceLabel(4), 'Learning');
      expect(trainingPerformanceLabel(6), 'Learning');
      expect(trainingPerformanceLabel(7), 'Good');
      expect(trainingPerformanceLabel(9), 'Good');
      expect(trainingPerformanceLabel(10), 'Great');
      expect(trainingPerformanceLabel(11), 'Great');
      expect(trainingPerformanceLabel(12), 'Mastered');
    });

    test('clamps out-of-range totals instead of throwing', () {
      expect(trainingPerformanceLabel(-1), 'Getting Started');
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
