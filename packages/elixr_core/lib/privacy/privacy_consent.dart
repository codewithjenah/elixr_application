/// Explicit, versioned legal consent captured before a profile is created.
///
/// Construction is intentionally private so callers cannot claim arbitrary
/// document versions. Existing profiles may omit these fields, but every new
/// registration must pass [current].
class RegistrationLegalConsent {
  const RegistrationLegalConsent._({
    required this.privacyPolicyVersion,
    required this.termsOfServiceVersion,
  });

  static const currentPrivacyPolicyVersion = 'v5';
  static const currentTermsOfServiceVersion = 'v2';

  final String privacyPolicyVersion;
  final String termsOfServiceVersion;

  static const RegistrationLegalConsent _current = RegistrationLegalConsent._(
    privacyPolicyVersion: currentPrivacyPolicyVersion,
    termsOfServiceVersion: currentTermsOfServiceVersion,
  );

  factory RegistrationLegalConsent.current() => _current;

  bool get isCurrent => identical(this, _current);

  /// Fields merged into `users/{uid}` on successful registration.
  ///
  /// [consentTimestamp] is normally `FieldValue.serverTimestamp()`; tests may
  /// inject a marker object.
  Map<String, dynamic> documentFields({required Object consentTimestamp}) {
    if (!isCurrent) {
      throw ArgumentError('Current registration legal consent is required.');
    }
    return {
      'privacy_consent_at': consentTimestamp,
      'privacy_policy_version': privacyPolicyVersion,
      'terms_consent_at': consentTimestamp,
      'terms_of_service_version': termsOfServiceVersion,
    };
  }
}

/// Backward-compatible version constant for consumers that display the
/// current privacy policy version without creating a profile.
abstract final class RegistrationPrivacyConsent {
  static const policyVersion =
      RegistrationLegalConsent.currentPrivacyPolicyVersion;
}
