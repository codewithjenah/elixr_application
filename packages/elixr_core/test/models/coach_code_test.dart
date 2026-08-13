import 'dart:math';

import 'package:elixr_core/models/coach_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoachCode.normalize', () {
    test('strips hyphens, spaces, and lowercases to uppercase', () {
      expect(CoachCode.normalize('7kpm-xr4d-q2wt'), '7KPMXR4DQ2WT');
      expect(CoachCode.normalize(' 7KPM XR4D Q2WT '), '7KPMXR4DQ2WT');
    });

    test('rejects ambiguous and short values via tryNormalize', () {
      expect(CoachCode.tryNormalize('ABC'), isNull);
      expect(CoachCode.tryNormalize('IIIIIIIIIIII'), isNull);
      expect(CoachCode.tryNormalize('000000000000'), isNull);
      expect(CoachCode.tryNormalize('7KPM-XR4D-Q2W!'), isNull);
    });

    test('accepts the example grouped format', () {
      expect(CoachCode.tryNormalize('7KPM-XR4D-Q2WT'), '7KPMXR4DQ2WT');
      expect(CoachCode.isNormalized('7KPMXR4DQ2WT'), isTrue);
    });
  });

  group('CoachCode.format', () {
    test('groups a normalized code in fours', () {
      expect(CoachCode.format('7KPMXR4DQ2WT'), '7KPM-XR4D-Q2WT');
    });

    test('throws for invalid input', () {
      expect(() => CoachCode.format('short'), throwsArgumentError);
    });
  });

  group('CoachCode.generateNormalized', () {
    test('uses only the ambiguity-safe alphabet and length 12', () {
      final rng = Random(42);
      final code = CoachCode.generateNormalized(random: rng);
      expect(code, hasLength(12));
      expect(CoachCode.isNormalized(code), isTrue);
      expect(RegExp(r'[IO01]').hasMatch(code), isFalse);
    });

    test('does not emit sequential or uid-like values', () {
      final first = CoachCode.generateNormalized(random: Random(1));
      final second = CoachCode.generateNormalized(random: Random(2));
      expect(first, isNot(second));
      expect(int.tryParse(first), isNull);
    });
  });
}
