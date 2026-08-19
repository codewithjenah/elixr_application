import 'package:elixr_core/repositories/auth_repository.dart';

/// User-facing copy for Teacher authentication flows in the Windows app.
abstract final class TeacherAuthMessages {
  static const notATeacher = 'This account is not registered as a Teacher.';
  static const passwordMismatch = 'Passwords do not match';
  static const passwordTooShort = 'Password must be at least 6 characters';
  static const legalConsentRequired =
      'Please agree to the Privacy Policy and Terms of Service.';
  static const missingProfile = MissingUserProfileException.message;
  static const emailNotVerifiedYet =
      'Email is not verified yet. Check your inbox and try again.';
  static const verificationSent = 'Verification email sent.';
}
