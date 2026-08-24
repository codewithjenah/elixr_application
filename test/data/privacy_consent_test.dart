import 'package:elixr_core/models/user.dart';
import 'package:elixr_application/data/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegistrationLegalConsent', () {
    test('documentFields writes current Privacy and Terms audit fields', () {
      const marker = 'server-timestamp-marker';

      expect(
        RegistrationLegalConsent.current().documentFields(
          consentTimestamp: marker,
        ),
        {
          'privacy_consent_at': marker,
          'privacy_policy_version': 'v5',
          'terms_consent_at': marker,
          'terms_of_service_version': 'v2',
        },
      );
      expect(RegistrationPrivacyConsent.policyVersion, 'v5');
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
        'terms_consent_at': consentedAt.toIso8601String(),
        'terms_of_service_version': 'v1',
      });

      expect(user.privacyConsentAt, consentedAt);
      expect(user.privacyPolicyVersion, 'v1');
      expect(user.termsConsentAt, consentedAt);
      expect(user.termsOfServiceVersion, 'v1');
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
      expect(user.termsConsentAt, isNull);
      expect(user.termsOfServiceVersion, isNull);
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
        termsConsentAt: consentedAt,
        termsOfServiceVersion: 'v1',
      );

      final map = user.toMap();

      expect(map['privacy_consent_at'], consentedAt.toIso8601String());
      expect(map['privacy_policy_version'], 'v1');
      expect(map['terms_consent_at'], consentedAt.toIso8601String());
      expect(map['terms_of_service_version'], 'v1');
    });
  });
}
