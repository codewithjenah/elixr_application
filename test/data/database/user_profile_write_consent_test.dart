import 'package:elixr_application/data/database/firestore_helper.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirestoreHelper.userProfileWriteData', () {
    test('includes consent fields only with an explicit legal contract', () {
      const user = User(
        id: 'u1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
      );

      final data = FirestoreHelper.userProfileWriteData(
        user,
        legalConsent: RegistrationLegalConsent.current(),
        serverTimestamp: () => 'SERVER_TS',
      );

      expect(data['privacy_consent_at'], 'SERVER_TS');
      expect(data['privacy_policy_version'], 'v5');
      expect(data['terms_consent_at'], 'SERVER_TS');
      expect(data['terms_of_service_version'], 'v2');
      expect(data['first_name'], 'Ada');
      expect(data['email'], 'ada@example.com');
    });

    test('omits privacy consent fields by default', () {
      const user = User(
        id: 'u1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
      );

      final data = FirestoreHelper.userProfileWriteData(user);

      expect(data.containsKey('privacy_consent_at'), isFalse);
      expect(data.containsKey('privacy_policy_version'), isFalse);
      expect(data.containsKey('terms_consent_at'), isFalse);
      expect(data.containsKey('terms_of_service_version'), isFalse);
    });
  });
}
