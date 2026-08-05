import 'package:elixr_application/core/utils/user_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('userInitials', () {
    test('empty or whitespace returns ?', () {
      expect(userInitials(''), '?');
      expect(userInitials('   '), '?');
    });

    test('single name returns first letter', () {
      expect(userInitials('Grace'), 'G');
      expect(userInitials('  ada  '), 'A');
    });

    test('multiple names use first and last tokens', () {
      expect(userInitials('Ada Lovelace'), 'AL');
      expect(userInitials('Grace Brewster Murray Hopper'), 'GH');
    });

    test('collapses extra whitespace', () {
      expect(userInitials('  Ada   Lovelace  '), 'AL');
    });
  });
}
