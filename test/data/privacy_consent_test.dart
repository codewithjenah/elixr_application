import 'package:elixr_core/models/user.dart';
import 'package:elixr_application/data/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegistrationPrivacyConsent', () {
    test('documentFields writes consent timestamp and policy version v2', () {
      const marker = 'server-timestamp-marker';

      expect(
        RegistrationPrivacyConsent.documentFields(consentTimestamp: marker),
        {'privacy_consent_at': marker, 'privacy_policy_version': 'v2'},
      );
      expect(RegistrationPrivacyConsent.policyVersion, 'v2');
    });
  });

  group('User privacy consent fields', () {
    test('fromMap parses privacy_consent_at and privacy_policy_version', () {
      final consentedAt = DateTime.utc(2026, 8, 10, 1, 2, 3);

      final user = User.fromMap({
        'id': 'u1',
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'email': 'ada@example.com',
        'privacy_consent_at': consentedAt.toIso8601String(),
        'privacy_policy_version': 'v1',
      });

      expect(user.privacyConsentAt, consentedAt);
      expect(user.privacyPolicyVersion, 'v1');
    });

    test('fromMap leaves consent fields null when absent', () {
      final user = User.fromMap({
        'id': 'u1',
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'email': 'ada@example.com',
      });

      expect(user.privacyConsentAt, isNull);
      expect(user.privacyPolicyVersion, isNull);
    });

    test('toMap writes consent fields when present', () {
      final consentedAt = DateTime.utc(2026, 8, 10, 1, 2, 3);
      final user = User(
        id: 'u1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        privacyConsentAt: consentedAt,
        privacyPolicyVersion: 'v1',
      );

      final map = user.toMap();

      expect(map['privacy_consent_at'], consentedAt.toIso8601String());
      expect(map['privacy_policy_version'], 'v1');
    });
  });
}
