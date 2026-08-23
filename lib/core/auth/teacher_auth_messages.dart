import 'package:elixr_core/repositories/auth_repository.dart';

/// User-facing copy for Windows authentication flows (Teacher gate + fail-closed roles).
abstract final class TeacherAuthMessages {
  static const notATeacher = 'This account is not registered as a Teacher.';
  static const passwordMismatch = 'Passwords do not match';
  static const passwordTooShort = 'Password must be at least 6 characters';
  static const legalConsentRequired =
      'Please agree to the Privacy Policy and Terms of Service.';
  static const missingProfile = MissingUserProfileException.message;
  static const emailNotVerifiedYet =
      'Email is not verified yet. Check your inbox and try again.';
  static const accountDeletionRequiresVerifiedEmail =
      accountDeletionRequiresVerifiedEmailMessage;
  static const accountDeletionVerificationSent =
      'We sent a verification message to confirm this delete request. '
      'Click the link in that email, then enter the 6-digit code from the '
      'page address (deleteCode=).';
  static const accountDeletionInvalidConfirmationCode =
      'That confirmation code is incorrect. Open the verification email link and try again.';
  static const teacherAuthorizationRefreshRequired =
      'Teacher verification needs to be refreshed. Verify your email and try again.';
  static const verificationSent = 'Verification email sent.';
  static const unsupportedRole =
      'This account cannot access ELIXR. Sign in with a Trainee or Teacher account.';
  static const accessCodeRequired =
      'Enter the Teacher access code provided by an administrator or an existing Teacher.';
  static const accessCodeInvalid =
      'That Teacher access code is not valid. Check the code and try again.';
}
