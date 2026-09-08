import 'dart:io';

import 'package:elixr_application/core/progression/official_supported_props.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;

  test('Functions OFFICIAL_MOVEMENT_PROPS matches Flutter catalog', () {
    final source = File('$repoRoot/functions/index.js').readAsStringSync();
    final begin = source.indexOf('// OFFICIAL_MOVEMENT_PROPS_BEGIN');
    final end = source.indexOf('// OFFICIAL_MOVEMENT_PROPS_END');
    expect(begin, greaterThanOrEqualTo(0));
    expect(end, greaterThan(begin));
    final block = source.substring(begin, end);
    final expected = officialSupportedPracticeVariants();
    final parsed = _parseJsOfficialProps(block);
    expect(parsed, expected);
  });

  test(
    'Firestore Rules officialMovementSupportsProp matches Flutter catalog',
    () {
      final source = File('$repoRoot/firestore.rules').readAsStringSync();
      final begin = source.indexOf('// OFFICIAL_MOVEMENT_PROPS_BEGIN');
      final end = source.indexOf('// OFFICIAL_MOVEMENT_PROPS_END');
      expect(begin, greaterThanOrEqualTo(0));
      expect(end, greaterThan(begin));
      final block = source.substring(begin, end);
      final expected = officialSupportedPracticeVariants();
      final parsed = _parseRulesOfficialProps(block);
      expect(parsed, expected);
    },
  );

  test('all 16 progression milestones are official supported pairs', () {
    final supported = officialSupportedPracticeVariants();
    for (final milestone in progressionMilestones) {
      expect(supported.contains(milestone.variant), isTrue);
    }
  });
}

Set<PracticeVariant> _parseJsOfficialProps(String block) {
  final result = <PracticeVariant>{};
  final entry = RegExp(
    r"\['((?:\\'|[^'])*)',\s*\[([^\]]*)\]\]|"
    r'\["((?:\\"|[^"])*)",\s*\[([^\]]*)\]\]',
  );
  for (final match in entry.allMatches(block)) {
    final name = (match.group(1) ?? match.group(3))!.replaceAll(r"\'", "'");
    final propsRaw = match.group(2) ?? match.group(4)!;
    for (final propMatch in RegExp(r"'([^']+)'").allMatches(propsRaw)) {
      final variant = PracticeVariant.tryParsePersistenceKey(
        '$name|${propMatch.group(1)}',
      );
      expect(variant, isNotNull, reason: '$name|${propMatch.group(1)}');
      result.add(variant!);
    }
  }
  return result;
}

Set<PracticeVariant> _parseRulesOfficialProps(String block) {
  final result = <PracticeVariant>{};
  final single = RegExp(
    r"""\(name == '([^']+)' && prop == '([^']+)'\)"""
    r'|'
    r'''\(name == "([^"]+)" && prop == '([^']+)'\)''',
  );
  for (final match in single.allMatches(block)) {
    final name = match.group(1) ?? match.group(3)!;
    final prop = match.group(2) ?? match.group(4)!;
    result.add(PracticeVariant.tryParsePersistenceKey('$name|$prop')!);
  }
  final multi = RegExp(r"""\(name == '([^']+)' && prop in \[([^\]]+)\]\)""");
  for (final match in multi.allMatches(block)) {
    final name = match.group(1)!;
    for (final propMatch in RegExp(r"'([^']+)'").allMatches(match.group(2)!)) {
      result.add(
        PracticeVariant.tryParsePersistenceKey('$name|${propMatch.group(1)}')!,
      );
    }
  }
  return result;
}
