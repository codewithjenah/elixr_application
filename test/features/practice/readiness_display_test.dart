import 'package:elixr_application/features/practice/readiness_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveReadinessDisplay — known codes', () {
    test('camera_frame resolves to short title Camera', () {
      final info = resolveReadinessDisplay('camera_frame');
      expect(info.title, 'Camera');
      expect(info.instruction, 'Live camera frame received.');
    });

    test('prop_detected resolves correctly', () {
      final info = resolveReadinessDisplay('prop_detected');
      expect(info.title, 'Selected Prop');
      expect(info.instruction, isNotEmpty);
    });

    test('bottle_detected resolves to short title Bottle', () {
      final info = resolveReadinessDisplay('bottle_detected');
      expect(info.title, 'Bottle');
      expect(info.instruction, 'Keep the bottle fully inside the frame.');
    });

    test('shaker_detected resolves to Cocktail Shaker', () {
      final info = resolveReadinessDisplay('shaker_detected');
      expect(info.title, 'Cocktail Shaker');
      expect(
        info.instruction,
        'Keep the cocktail shaker fully inside the frame.',
      );
    });

    test('prop_count_two resolves to Two Bottles', () {
      final info = resolveReadinessDisplay('prop_count_two');
      expect(info.title, 'Two Bottles');
      expect(info.instruction, 'Keep two bottles fully inside the frame.');
    });

    test('grip_landmarks_visible resolves to Grip Hand', () {
      final info = resolveReadinessDisplay('grip_landmarks_visible');
      expect(info.title, 'Grip Hand');
      expect(info.instruction, 'Keep the full gripping hand visible.');
    });

    test('palm_landmarks_visible resolves to Hand Center', () {
      final info = resolveReadinessDisplay('palm_landmarks_visible');
      expect(info.title, 'Hand Center');
      expect(info.instruction, 'Keep the center of your hand visible.');
    });

    test('index_landmarks_visible resolves to Index Finger', () {
      final info = resolveReadinessDisplay('index_landmarks_visible');
      expect(info.title, 'Index Finger');
      expect(
        info.instruction,
        'Keep the index-finger tracking points visible.',
      );
    });

    test('two_hands_visible resolves to Both Hands', () {
      final info = resolveReadinessDisplay('two_hands_visible');
      expect(info.title, 'Both Hands');
      expect(info.instruction, 'Keep both hands fully inside the frame.');
    });

    test('supporting_hand_visible resolves to Supporting Hand', () {
      final info = resolveReadinessDisplay('supporting_hand_visible');
      expect(info.title, 'Supporting Hand');
      expect(info.instruction, 'Keep a supporting hand visible in the frame.');
    });

    test('pose_forearm_or_hand resolves to Arm or Hand', () {
      final info = resolveReadinessDisplay('pose_forearm_or_hand');
      expect(info.title, 'Arm or Hand');
      expect(info.instruction, isNotEmpty);
    });

    test('pose_upper_forearm resolves to Upper Arm', () {
      final info = resolveReadinessDisplay('pose_upper_forearm');
      expect(info.title, 'Upper Arm');
      expect(info.instruction, isNotEmpty);
    });

    test('pose_shoulder resolves to Shoulder', () {
      final info = resolveReadinessDisplay('pose_shoulder');
      expect(info.title, 'Shoulder');
      expect(info.instruction, isNotEmpty);
    });

    test(
      'upper_body_visible resolves to Upper Body with correct instruction',
      () {
        final info = resolveReadinessDisplay('upper_body_visible');
        expect(info.title, 'Upper Body');
        expect(
          info.instruction,
          'Keep both shoulders and at least one complete arm visible.',
        );
      },
    );
  });

  group('resolveReadinessDisplay — unknown codes', () {
    test(
      'unknown code uses humanized code as title and backendMessage as instruction',
      () {
        const msg = 'Adjust your lighting';
        final info = resolveReadinessDisplay(
          'custom_lighting_check',
          backendMessage: msg,
        );
        // Title is the humanized code; instruction is the backend message.
        expect(info.title, 'Custom Lighting Check');
        expect(info.instruction, msg);
      },
    );

    test('unknown code without backendMessage humanizes code as title', () {
      final info = resolveReadinessDisplay('future_check_xyz');
      expect(info.title, 'Future Check Xyz');
      expect(info.instruction, isNotEmpty);
    });

    test(
      'unknown code with backendMessage equal to humanized title uses generic instruction',
      () {
        // If backend message happens to equal the humanized title we avoid
        // showing it twice — fall back to generic instruction instead.
        final humanized = 'Future Check Xyz';
        final info = resolveReadinessDisplay(
          'future_check_xyz',
          backendMessage: humanized,
        );
        expect(info.title, humanized);
        expect(info.instruction, isNot(humanized));
        expect(info.instruction, isNotEmpty);
      },
    );

    test('empty backendMessage still yields a non-empty instruction', () {
      final info = resolveReadinessDisplay('unknown_code', backendMessage: '');
      expect(info.title, isNotEmpty);
      expect(info.instruction, isNotEmpty);
    });
  });

  group('ReadinessDisplayInfo', () {
    test('fields are set correctly', () {
      const info = ReadinessDisplayInfo(
        title: 'My Title',
        instruction: 'My Instruction',
      );
      expect(info.title, 'My Title');
      expect(info.instruction, 'My Instruction');
    });
  });
}
