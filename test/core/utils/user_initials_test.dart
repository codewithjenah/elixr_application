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

    test('uses first and last display-name tokens', () {
      expect(userInitials('Anton Jiro Yumul'), 'AY');
    });

    test('multiple names use first and last tokens', () {
      expect(userInitials('Ada Lovelace'), 'AL');
      expect(userInitials('Grace Brewster Murray Hopper'), 'GH');
    });

    test('collapses extra whitespace', () {
      expect(userInitials('  Ada   Lovelace  '), 'AL');
    });

    test('keeps Unicode grapheme clusters intact', () {
      expect(userInitials('👩‍🔬 Rivera'), '👩‍🔬R');
      expect(userInitials('e\u0301clair Doe'), 'E\u0301D');
    });
  });
}
