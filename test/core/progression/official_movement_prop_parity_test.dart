import 'dart:io';

import 'package:elixr_application/core/progression/official_supported_props.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('database official_movement_props matches Flutter catalog', () {
    final source = File(
      'supabase/migrations/20260926000100_elixr_core.sql',
    ).readAsStringSync();
    final start = source.indexOf('function private.official_movement_props(');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf(r'$$;', start);
    final block = source.substring(start, end);
    final parsed = <PracticeVariant>{};
    final entry = RegExp(r"when '((?:''|[^'])+)' then array\[([^\]]*)\]");
    for (final match in entry.allMatches(block)) {
      final name = match.group(1)!.replaceAll("''", "'");
      for (final prop in RegExp(r"'([^']+)'").allMatches(match.group(2)!)) {
        final variant = PracticeVariant.tryParsePersistenceKey(
          '$name|${prop.group(1)}',
        );
        expect(variant, isNotNull, reason: '$name|${prop.group(1)}');
        parsed.add(variant!);
      }
    }
    expect(parsed, officialSupportedPracticeVariants());
  });

  test('all 20 progression milestones are official supported pairs', () {
    final supported = officialSupportedPracticeVariants();
    for (final milestone in progressionMilestones) {
      expect(supported.contains(milestone.variant), isTrue);
    }
  });
}
