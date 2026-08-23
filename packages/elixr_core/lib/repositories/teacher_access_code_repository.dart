import '../models/teacher_access_code.dart';
import '../models/user.dart';

/// One-time Teacher access codes used to gate `role: Teacher` registration.
abstract class TeacherAccessCodeRepository {
  /// Throws if [code] is missing, malformed, unknown, or already consumed.
  ///
  /// Used to fail closed before Firebase Auth account creation.
  Future<void> assertRedeemable(String? code);

  /// Atomically marks [code] consumed and creates the Teacher `users/{uid}`
  /// document. Must run in the same Firestore transaction/batch as the user
  /// create so security rules can see both writes.
  Future<void> consumeAndCreateTeacherProfile({
    required String code,
    required User user,
    bool includePrivacyConsent = true,
  });

  /// Mints a fresh unconsumed code for an existing Teacher to share.
  Future<TeacherAccessCode> mint({required String createdBy, String? note});
}
