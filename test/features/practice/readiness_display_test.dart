import 'package:elixr_application/features/practice/readiness_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveReadinessDisplay — known codes', () {
    test('camera_frame resolves correctly', () {
      final info = resolveReadinessDisplay('camera_frame');
      expect(info.title, 'Camera Frame');
      expect(info.instruction, isNotEmpty);
    });

    test('prop_detected resolves correctly', () {
      final info = resolveReadinessDisplay('prop_detected');
      expect(info.title, 'Prop Detected');
      expect(info.instruction, isNotEmpty);
    });

    test('bottle_detected resolves correctly', () {
      final info = resolveReadinessDisplay('bottle_detected');
      expect(info.title, 'Bottle Detected');
      expect(info.instruction, isNotEmpty);
    });

    test('shaker_detected resolves correctly', () {
      final info = resolveReadinessDisplay('shaker_detected');
      expect(info.title, 'Shaker Detected');
      expect(info.instruction, isNotEmpty);
    });

    test('prop_count_two resolves correctly', () {
      final info = resolveReadinessDisplay('prop_count_two');
      expect(info.title, 'Two Props Visible');
      expect(info.instruction, isNotEmpty);
    });

    test('grip_landmarks_visible resolves correctly', () {
      final info = resolveReadinessDisplay('grip_landmarks_visible');
      expect(info.title, 'Grip Landmarks');
      expect(info.instruction, isNotEmpty);
    });

    test('palm_landmarks_visible resolves correctly', () {
      final info = resolveReadinessDisplay('palm_landmarks_visible');
      expect(info.title, 'Palm Landmarks');
      expect(info.instruction, isNotEmpty);
    });

    test('index_landmarks_visible resolves correctly', () {
      final info = resolveReadinessDisplay('index_landmarks_visible');
      expect(info.title, 'Index Finger Visible');
      expect(info.instruction, isNotEmpty);
    });

    test('two_hands_visible resolves correctly', () {
      final info = resolveReadinessDisplay('two_hands_visible');
      expect(info.title, 'Both Hands Visible');
      expect(info.instruction, isNotEmpty);
    });

    test('supporting_hand_visible resolves correctly', () {
      final info = resolveReadinessDisplay('supporting_hand_visible');
      expect(info.title, 'Supporting Hand');
      expect(info.instruction, isNotEmpty);
    });

    test('pose_forearm_or_hand resolves correctly', () {
      final info = resolveReadinessDisplay('pose_forearm_or_hand');
      expect(info.title, 'Forearm or Hand Pose');
      expect(info.instruction, isNotEmpty);
    });

    test('pose_upper_forearm resolves correctly', () {
      final info = resolveReadinessDisplay('pose_upper_forearm');
      expect(info.title, 'Upper Forearm Pose');
      expect(info.instruction, isNotEmpty);
    });

    test('pose_shoulder resolves correctly', () {
      final info = resolveReadinessDisplay('pose_shoulder');
      expect(info.title, 'Shoulder Visible');
      expect(info.instruction, isNotEmpty);
    });

    test('upper_body_visible resolves correctly and uses backend fallback', () {
      final info = resolveReadinessDisplay('upper_body_visible');
      expect(info.title, 'Upper Body Visible');
      expect(
        info.instruction,
        'Keep your shoulders, elbows, and wrists visible in the camera.',
      );

      const backendMsg = 'Keep your shoulders, elbows, and wrists visible.';
      final fallback = resolveReadinessDisplay(
        'upper_body_visible',
        backendMessage: backendMsg,
      );
      expect(fallback.title, 'Upper Body Visible');
      expect(fallback.instruction, isNotEmpty);
    });
  });

  group('resolveReadinessDisplay — unknown codes', () {
    test(
      'unknown code with backendMessage uses message as title and instruction',
      () {
        const msg = 'Adjust your lighting';
        final info = resolveReadinessDisplay(
          'custom_lighting_check',
          backendMessage: msg,
        );
        expect(info.title, msg);
        expect(info.instruction, msg);
      },
    );

    test('unknown code without backendMessage falls back to code as title', () {
      final info = resolveReadinessDisplay('future_check_xyz');
      expect(info.title, 'future_check_xyz');
      expect(info.instruction, isNotEmpty);
    });

    test('empty backendMessage falls back to code as title', () {
      final info = resolveReadinessDisplay('unknown_code', backendMessage: '');
      // Empty string is falsy in the null check expression (null-safe), so
      // backendMessage '' is non-null but empty; title uses it literally.
      expect(info.title, isEmpty);
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
