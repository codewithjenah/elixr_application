import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';

class FakeAuthRepository implements AuthRepositoryBase {
  User? persistedUser;
  bool emailVerified = false;
  Object? loginError;
  Object? registerError;
  Object? passwordResetError;
  Object? verificationError;
  Object? loadError;
  Object? refreshError;
  Object? signOutError;
  User? loginResult;
  Completer<void>? registerGate;
  Completer<void>? loginGate;

  int registerCallCount = 0;
  int loginCallCount = 0;
  int clearCurrentUserCallCount = 0;
  int sendPasswordResetEmailCallCount = 0;
  int requestVerificationCallCount = 0;
  int isCurrentEmailVerifiedCallCount = 0;
  int refreshAuthenticatedUserCallCount = 0;

  String? lastDefaultRole;
  String? lastRegisterEmail;
  String? lastRegisterFirstName;
  String? lastRegisterMiddleName;
  String? lastRegisterLastName;
  String? lastPasswordResetEmail;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
  }) async {
    registerCallCount++;
    lastDefaultRole = defaultRole;
    lastRegisterEmail = email;
    lastRegisterFirstName = firstName;
    lastRegisterMiddleName = middleName;
    lastRegisterLastName = lastName;
    final gate = registerGate;
    if (gate != null) await gate.future;
    if (registerError != null) throw registerError!;
    final user = User(
      id: 'teacher-1',
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      role: defaultRole,
    );
    persistedUser = user;
    emailVerified = false;
    return user;
  }

  @override
  Future<User> login({required String email, required String password}) async {
    loginCallCount++;
    final gate = loginGate;
    if (gate != null) await gate.future;
    if (loginError != null) throw loginError!;
    final user = loginResult ?? persistedUser;
    if (user == null) {
      throw Exception('Invalid email or password');
    }
    persistedUser = user;
    return user;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    sendPasswordResetEmailCallCount++;
    lastPasswordResetEmail = email;
    if (passwordResetError != null) throw passwordResetError!;
  }

  @override
  Future<User?> loadPersistedUser() async {
    if (loadError != null) throw loadError!;
    return persistedUser;
  }

  @override
  Future<void> clearCurrentUser() async {
    clearCurrentUserCallCount++;
    if (signOutError != null) throw signOutError!;
    persistedUser = null;
  }

  @override
  Future<bool> isCurrentEmailVerified() async {
    isCurrentEmailVerifiedCallCount++;
    return emailVerified;
  }

  @override
  Future<void> requestCurrentEmailVerification() async {
    requestVerificationCallCount++;
    if (verificationError != null) throw verificationError!;
  }

  @override
  Future<User?> refreshAuthenticatedUser() async {
    refreshAuthenticatedUserCallCount++;
    if (refreshError != null) throw refreshError!;
    return persistedUser;
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> deleteAccount({required String password}) async {}
}

User fakeTeacher({
  String email = 'teacher@example.com',
  String firstName = 'Ada',
  String lastName = 'Lovelace',
}) {
  return User(
    id: 'teacher-1',
    firstName: firstName,
    lastName: lastName,
    email: email,
    role: User.roleTeacher,
  );
}

User fakeTrainee({String email = 'trainee@example.com'}) {
  return User(
    id: 'trainee-1',
    firstName: 'Trainee',
    lastName: 'User',
    email: email,
    role: User.roleTrainee,
  );
}

User fakeAdmin({String email = 'admin@example.com'}) {
  return User(
    id: 'admin-1',
    firstName: 'Admin',
    lastName: 'User',
    email: email,
    role: User.roleAdmin,
  );
}
