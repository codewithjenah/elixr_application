import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:flutter/foundation.dart';

enum TeacherAuthStatus {
  initializing,
  signedOut,
  unverifiedTeacher,
  authenticatedTeacher,
}

abstract final class TeacherAuthMessages {
  static const notATeacher = 'This account is not registered as a Teacher.';
  static const passwordMismatch = 'Passwords do not match';
  static const passwordTooShort = 'Password must be at least 6 characters';
  static const legalConsentRequired =
      'Please agree to the Privacy Policy and Terms of Service.';
  static const emailEmpty = 'Email cannot be empty.';
  static const invalidEmail = 'Invalid email address';
  static const resetEmailSent = 'Check your email for a reset link';
  static const missingProfile = MissingUserProfileException.message;
  static const emailNotVerifiedYet =
      'Email is not verified yet. Check your inbox and try again.';
  static const verificationSent = 'Verification email sent.';
  static const genericFailure = 'Something went wrong. Please try again.';
}

/// Teacher-app authentication state. Delegates Firebase work to [AuthRepositoryBase].
class TeacherAuthController extends ChangeNotifier {
  TeacherAuthController({required this.repository, this.awaitInitialAuthState});

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const _minPasswordLength = 6;

  final AuthRepositoryBase repository;
  final Future<void> Function()? awaitInitialAuthState;

  TeacherAuthStatus _status = TeacherAuthStatus.initializing;
  User? _currentUser;
  bool _isBusy = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _disposed = false;
  Future<void>? _initializeFuture;

  TeacherAuthStatus get status => _status;
  User? get currentUser => _currentUser;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;

  bool get isInitializing => _status == TeacherAuthStatus.initializing;
  bool get isSignedOut => _status == TeacherAuthStatus.signedOut;
  bool get needsEmailVerification =>
      _status == TeacherAuthStatus.unverifiedTeacher;
  bool get canEnterTeacherShell =>
      _status == TeacherAuthStatus.authenticatedTeacher;

  Future<void> initialize() {
    return _initializeFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    _status = TeacherAuthStatus.initializing;
    _clearMessages();
    _emit();

    try {
      final awaitInitial = awaitInitialAuthState;
      if (awaitInitial != null) {
        await awaitInitial();
      }

      final user = await repository.loadPersistedUser();
      await _applyAuthenticatedUser(user, fromPersistedSession: true);
    } catch (error) {
      _currentUser = null;
      _status = TeacherAuthStatus.signedOut;
      _errorMessage = sanitizeAuthError(error);
      _emit();
    }
  }

  Future<bool> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String confirmPassword,
    required bool legalConsent,
  }) async {
    if (!_beginOperation()) return false;

    try {
      if (!legalConsent) {
        _errorMessage = TeacherAuthMessages.legalConsentRequired;
        return false;
      }

      final nameError = validateUserNameParts(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
      );
      if (nameError != null) {
        _errorMessage = nameError;
        return false;
      }

      final trimmedEmail = email.trim();
      final emailError = _validateEmail(trimmedEmail);
      if (emailError != null) {
        _errorMessage = emailError;
        return false;
      }

      if (password.length < _minPasswordLength) {
        _errorMessage = TeacherAuthMessages.passwordTooShort;
        return false;
      }
      if (password != confirmPassword) {
        _errorMessage = TeacherAuthMessages.passwordMismatch;
        return false;
      }

      _isBusy = true;
      _emit();

      final normalized = normalizeUserNameParts(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
      );
      final user = await repository.register(
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
        email: trimmedEmail,
        password: password,
        defaultRole: User.roleTeacher,
      );

      if (!user.isTeacher) {
        await _rejectNonTeacherSession();
        return false;
      }

      _currentUser = user;
      try {
        await repository.requestCurrentEmailVerification();
        _infoMessage = TeacherAuthMessages.verificationSent;
      } catch (error) {
        _errorMessage = sanitizeAuthError(error);
      }

      final verified = await _readEmailVerified(failClosed: true);
      _status = verified
          ? TeacherAuthStatus.authenticatedTeacher
          : TeacherAuthStatus.unverifiedTeacher;
      return true;
    } catch (error) {
      await _abandonRemoteSession();
      _errorMessage = _failureMessage(error);
      return false;
    } finally {
      _isBusy = false;
      _emit();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    if (!_beginOperation()) return false;

    try {
      final trimmedEmail = email.trim();
      final emailError = _validateEmail(trimmedEmail);
      if (emailError != null) {
        _errorMessage = emailError;
        return false;
      }
      if (password.isEmpty) {
        _errorMessage = 'Password cannot be empty.';
        return false;
      }

      _isBusy = true;
      _emit();

      final user = await repository.login(
        email: trimmedEmail,
        password: password,
      );
      return _applyAuthenticatedUser(user, fromPersistedSession: false);
    } catch (error) {
      await _abandonRemoteSession();
      _errorMessage = _failureMessage(error);
      return false;
    } finally {
      _isBusy = false;
      _emit();
    }
  }

  Future<bool> sendPasswordResetEmail({required String email}) async {
    if (!_beginOperation()) return false;

    try {
      final trimmedEmail = email.trim();
      final emailError = _validateEmail(trimmedEmail);
      if (emailError != null) {
        _errorMessage = emailError;
        return false;
      }

      _isBusy = true;
      _emit();

      await repository.sendPasswordResetEmail(email: trimmedEmail);
      _infoMessage = TeacherAuthMessages.resetEmailSent;
      return true;
    } catch (error) {
      if (isAccountEnumerationResetError(error)) {
        _infoMessage = TeacherAuthMessages.resetEmailSent;
        return true;
      }
      _errorMessage = sanitizeAuthError(error);
      return false;
    } finally {
      _isBusy = false;
      _emit();
    }
  }

  Future<bool> resendVerificationEmail() async {
    if (!_beginOperation()) return false;
    if (_status != TeacherAuthStatus.unverifiedTeacher) {
      _errorMessage = TeacherAuthMessages.genericFailure;
      _emit();
      return false;
    }

    _isBusy = true;
    _emit();
    try {
      await repository.requestCurrentEmailVerification();
      _infoMessage = TeacherAuthMessages.verificationSent;
      return true;
    } catch (error) {
      _errorMessage = sanitizeAuthError(error);
      return false;
    } finally {
      _isBusy = false;
      _emit();
    }
  }

  Future<bool> checkEmailVerification() async {
    if (!_beginOperation()) return false;
    if (_status != TeacherAuthStatus.unverifiedTeacher) {
      _errorMessage = TeacherAuthMessages.genericFailure;
      _emit();
      return false;
    }

    _isBusy = true;
    _emit();
    try {
      final verified = await repository.isCurrentEmailVerified();
      if (!verified) {
        _errorMessage = TeacherAuthMessages.emailNotVerifiedYet;
        return false;
      }

      final user = await repository.refreshAuthenticatedUser();
      return _applyAuthenticatedUser(user, fromPersistedSession: false);
    } catch (error) {
      _errorMessage = sanitizeAuthError(error);
      return false;
    } finally {
      _isBusy = false;
      _emit();
    }
  }

  Future<void> signOut() async {
    if (_isBusy) return;
    _isBusy = true;
    _clearMessages();
    _emit();
    try {
      await repository.clearCurrentUser();
    } catch (error) {
      // Local sign-out still proceeds so a stuck Firebase session cannot trap
      // the user inside the Teacher shell.
      _errorMessage = sanitizeAuthError(error);
    } finally {
      _currentUser = null;
      _status = TeacherAuthStatus.signedOut;
      _isBusy = false;
      _emit();
    }
  }

  void clearMessages() {
    if (_errorMessage == null && _infoMessage == null) return;
    _clearMessages();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _beginOperation() {
    if (_isBusy || _status == TeacherAuthStatus.initializing) {
      return false;
    }
    _clearMessages();
    return true;
  }

  Future<bool> _applyAuthenticatedUser(
    User? user, {
    required bool fromPersistedSession,
  }) async {
    if (user == null) {
      _currentUser = null;
      _status = TeacherAuthStatus.signedOut;
      return false;
    }

    if (!user.isTeacher) {
      await _rejectNonTeacherSession();
      return false;
    }

    _currentUser = user;
    final verified = await _readEmailVerified(
      failClosed: !fromPersistedSession,
    );
    _status = verified
        ? TeacherAuthStatus.authenticatedTeacher
        : TeacherAuthStatus.unverifiedTeacher;
    return true;
  }

  Future<void> _rejectNonTeacherSession() async {
    await _abandonRemoteSession();
    _errorMessage = TeacherAuthMessages.notATeacher;
  }

  Future<void> _abandonRemoteSession() async {
    try {
      await repository.clearCurrentUser();
    } catch (_) {
      // Keep the Teacher app signed out even if remote sign-out fails.
    }
    _currentUser = null;
    _status = TeacherAuthStatus.signedOut;
  }

  String _failureMessage(Object error) {
    if (error is MissingUserProfileException) {
      return TeacherAuthMessages.missingProfile;
    }
    return sanitizeAuthError(error);
  }

  Future<bool> _readEmailVerified({required bool failClosed}) async {
    try {
      return await repository.isCurrentEmailVerified();
    } catch (error) {
      if (failClosed) {
        _errorMessage ??= sanitizeAuthError(error);
        return false;
      }
      return false;
    }
  }

  String? _validateEmail(String trimmedEmail) {
    if (trimmedEmail.isEmpty) return TeacherAuthMessages.emailEmpty;
    if (!_emailPattern.hasMatch(trimmedEmail)) {
      return TeacherAuthMessages.invalidEmail;
    }
    return null;
  }

  void _clearMessages() {
    _errorMessage = null;
    _infoMessage = null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }
}

@visibleForTesting
bool isAccountEnumerationResetError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('user-not-found') ||
      lower.contains('user not found') ||
      lower.contains('no user record');
}

@visibleForTesting
String sanitizeAuthError(Object error) {
  var message = error.toString();
  const prefix = 'Exception: ';
  if (message.startsWith(prefix)) {
    message = message.substring(prefix.length);
  }

  final lower = message.toLowerCase();
  if (lower.contains('firebaseexception') ||
      lower.contains('firebaseauthexception') ||
      message.contains('\n') ||
      lower.contains('#0 ')) {
    return TeacherAuthMessages.genericFailure;
  }
  if (message.trim().isEmpty) return TeacherAuthMessages.genericFailure;
  return message;
}
