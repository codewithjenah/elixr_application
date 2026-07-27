import 'package:elixr_application/features/practice/widgets/training_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trainingPerformanceLabel', () {
    test('Excellent at 85–100', () {
      expect(trainingPerformanceLabel(85), 'Excellent');
      expect(trainingPerformanceLabel(100), 'Excellent');
    });

    test('Developing at 70–84', () {
      expect(trainingPerformanceLabel(70), 'Developing');
      expect(trainingPerformanceLabel(84), 'Developing');
    });

    test('Needs Practice below 70', () {
      expect(trainingPerformanceLabel(69), 'Needs Practice');
      expect(trainingPerformanceLabel(0), 'Needs Practice');
    });
  });

  group('trainingPerformanceFraction', () {
    test('null is 0', () {
      expect(trainingPerformanceFraction(null), 0.0);
    });

    test('clamps below 0 and above 100', () {
      expect(trainingPerformanceFraction(-10), 0.0);
      expect(trainingPerformanceFraction(150), 1.0);
      expect(trainingPerformanceFraction(50), 0.5);
    });
  });
}
