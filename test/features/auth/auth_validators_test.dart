import 'package:elixr_application/features/auth/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateAuthEmail', () {
    test('trims and accepts a conventional address', () {
      expect(validateAuthEmail('  trainee@example.com  '), isNull);
    });

    test('rejects empty and malformed addresses', () {
      expect(validateAuthEmail('   '), 'Email address is required.');
      expect(validateAuthEmail('trainee@example'), isNotNull);
      expect(validateAuthEmail('@example.com'), isNotNull);
    });
  });

  group('registration password validation', () {
    test('accepts the eight-character boundary with a letter and number', () {
      expect(validateRegistrationPassword('secret12'), isNull);
    });

    test('rejects short, letter-only, and number-only passwords', () {
      expect(validateRegistrationPassword('abc1234'), isNotNull);
      expect(validateRegistrationPassword('abcdefgh'), isNotNull);
      expect(validateRegistrationPassword('12345678'), isNotNull);
    });

    test('validates confirmation independently', () {
      expect(validatePasswordConfirmation('secret12', ''), isNotNull);
      expect(validatePasswordConfirmation('secret12', 'secret13'), isNotNull);
      expect(validatePasswordConfirmation('secret12', 'secret12'), isNull);
    });
  });
}
