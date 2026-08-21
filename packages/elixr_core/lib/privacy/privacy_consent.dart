/// Registration-time privacy consent markers for RA 10173 tracking.
abstract final class RegistrationPrivacyConsent {
  static const policyVersion = 'v4';

  /// Fields merged into `users/{uid}` on successful registration.
  ///
  /// [consentTimestamp] is normally `FieldValue.serverTimestamp()`; tests may
  /// inject a marker object.
  static Map<String, dynamic> documentFields({
    required Object consentTimestamp,
  }) {
    return {
      'privacy_consent_at': consentTimestamp,
      'privacy_policy_version': policyVersion,
    };
  }
}
