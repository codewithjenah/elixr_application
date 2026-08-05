import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/profile_image_repository.dart';

class _PendingEmailChangeState {
  _PendingEmailChangeState({
    required this.originalUid,
    required this.originalEmail,
    required this.pendingEmail,
    required String password,
    required this.expiresAt,
  }) : _password = password;

  final String originalUid;
  final String originalEmail;
  final String pendingEmail;
  final DateTime expiresAt;
  String _password;

  String get password => _password;

  void clearPassword() {
    _password = '';
  }
}

class AuthService extends ChangeNotifier {
  AuthService({
    AuthRepositoryBase? repository,
    LeaderboardRepository? leaderboardRepository,
    ProfileImageRepositoryBase? profileImageRepository,
    Duration? pendingEmailPollInterval,
    Duration? pendingEmailTimeout,
  }) : _repository = repository ?? AuthRepository(),
       _leaderboardRepository = leaderboardRepository,
       _explicitProfileImageRepository = profileImageRepository,
       _pendingEmailPollInterval =
           pendingEmailPollInterval ?? const Duration(seconds: 5),
       _pendingEmailTimeout = pendingEmailTimeout ?? const Duration(minutes: 2);

  final AuthRepositoryBase _repository;
  final LeaderboardRepository? _leaderboardRepository;
  final Duration _pendingEmailPollInterval;
  final Duration _pendingEmailTimeout;

  // Lazily constructed so tests that never touch profile-image upload do not
  // need Firebase Storage initialized.
  ProfileImageRepositoryBase? _explicitProfileImageRepository;
  ProfileImageRepositoryBase get _profileImageRepository =>
      _explicitProfileImageRepository ??= ProfileImageRepository();

  User? _currentUser;
  bool _isLoading = true;
  bool _disposed = false;
  bool _checkingPendingEmail = false;
  _PendingEmailChangeState? _pendingEmailChange;
  Timer? _pendingEmailPollTimer;
  String? _pendingEmailRecoveryError;
  String? _pendingEmailChangeSuccessMessage;
  Future<void>? _pendingEmailCheckInFlight;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get pendingEmail => _pendingEmailChange?.pendingEmail;
  bool get hasPendingEmailChange =>
      _pendingEmailChange != null && !_isPendingEmailExpired;
  bool get isCheckingPendingEmailChange => _checkingPendingEmail;
  String? get pendingEmailRecoveryError => _pendingEmailRecoveryError;

  String? takePendingEmailChangeSuccessMessage() {
    final message = _pendingEmailChangeSuccessMessage;
    _pendingEmailChangeSuccessMessage = null;
    return message;
  }

  bool get _isPendingEmailExpired {
    final pending = _pendingEmailChange;
    if (pending == null) return true;
    return DateTime.now().isAfter(pending.expiresAt);
  }

  @visibleForTesting
  Future<void> waitForPendingEmailCheckIdle() async {
    while (_pendingEmailCheckInFlight != null || _checkingPendingEmail) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @visibleForTesting
  void seedAuthenticatedUser(User user) {
    _currentUser = user;
    _isLoading = false;
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    await fb.FirebaseAuth.instance.authStateChanges().first;
    _currentUser = await _repository.loadPersistedUser();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final user = await _repository.register(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      password: password,
    );
    _currentUser = user;
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    final user = await _repository.login(email: email, password: password);
    _currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    _clearPendingEmailChange(clearError: true);
    _currentUser = null;
    await _repository.clearCurrentUser();
    notifyListeners();
  }

  /// Updates the display name and, optionally, uploads a new profile
  /// avatar to Firebase Cloud Storage.
  ///
  /// When [newProfileImageBytes] and [newProfileImageContentType] are both
  /// provided, the image is uploaded first; Firestore is only updated after
  /// the upload succeeds. A name-only update never touches Cloud Storage.
  ///
  /// Prefer [updateProfilePicture] for image-only updates so unsaved name or
  /// email edits are never written as a side effect.
  Future<void> updateProfileDetails({
    required String firstName,
    String? middleName,
    required String lastName,
    Uint8List? newProfileImageBytes,
    String? newProfileImageContentType,
  }) async {
    if (_currentUser?.id == null) {
      throw Exception('Not authenticated');
    }
    final userId = _currentUser!.id!;
    final previousUser = _currentUser!;

    ProfilePictureUpdate? pictureUpdate;
    if (newProfileImageBytes != null && newProfileImageContentType != null) {
      pictureUpdate = await _uploadProfilePicture(
        userId: userId,
        bytes: newProfileImageBytes,
        contentType: newProfileImageContentType,
      );
    }

    try {
      _currentUser = await _repository.updateProfileDetails(
        userId: userId,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        profilePictureUpdate: pictureUpdate,
      );
    } catch (error) {
      if (pictureUpdate != null) {
        // Firestore did not accept the new image reference; do not leave an
        // orphaned object in Storage, and keep the previous profile intact.
        await _bestEffortDeleteImage(userId, pictureUpdate.storagePath);
      }
      rethrow;
    }

    notifyListeners();
    await _afterSuccessfulPictureUpdate(
      userId: userId,
      previousUser: previousUser,
      pictureUpdate: pictureUpdate,
    );
  }

  /// Uploads and persists a new profile avatar without writing name or email.
  ///
  /// Reuses [ProfileImageRepository] upload/delete rules (content type, 5 MB
  /// limit, ownership paths) and refreshes [currentUser] + listeners so all
  /// avatar consumers update.
  Future<void> updateProfilePicture({
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (_currentUser?.id == null) {
      throw Exception('Not authenticated');
    }
    final userId = _currentUser!.id!;
    final previousUser = _currentUser!;

    final pictureUpdate = await _uploadProfilePicture(
      userId: userId,
      bytes: bytes,
      contentType: contentType,
    );

    try {
      _currentUser = await _repository.updateProfilePicture(
        userId: userId,
        profilePictureUpdate: pictureUpdate,
      );
    } catch (error) {
      await _bestEffortDeleteImage(userId, pictureUpdate.storagePath);
      rethrow;
    }

    notifyListeners();
    await _afterSuccessfulPictureUpdate(
      userId: userId,
      previousUser: previousUser,
      pictureUpdate: pictureUpdate,
    );
  }

  Future<ProfilePictureUpdate> _uploadProfilePicture({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uploaded = await _profileImageRepository.uploadProfileImage(
      userId: userId,
      bytes: bytes,
      contentType: contentType,
    );
    return ProfilePictureUpdate(
      url: uploaded.downloadUrl,
      storagePath: uploaded.storagePath,
    );
  }

  Future<void> _afterSuccessfulPictureUpdate({
    required String userId,
    required User previousUser,
    required ProfilePictureUpdate? pictureUpdate,
  }) async {
    if (pictureUpdate != null) {
      final previousStoragePath = previousUser.profilePictureStoragePath;
      if (previousStoragePath != null && previousStoragePath.isNotEmpty) {
        await _bestEffortDeleteImage(userId, previousStoragePath);
      }
    }

    try {
      await _leaderboardRepository?.syncPublicProfile(
        userId: userId,
        displayName: _currentUser?.fullName ?? '',
        profilePictureUrl: _currentUser?.profilePictureUrl,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Leaderboard public profile sync failed: userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  /// Best-effort Storage cleanup. Intentionally swallows failures: a
  /// dangling object is a minor storage-cost issue, not a correctness bug,
  /// and must never surface as a profile-save failure to the user.
  Future<void> _bestEffortDeleteImage(String userId, String storagePath) async {
    try {
      await _profileImageRepository.deleteProfileImage(
        authenticatedUid: userId,
        storagePath: storagePath,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Profile image cleanup failed: userId=$userId path=$storagePath error=$error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  Future<bool> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    final result = await _repository.requestEmailChange(
      newEmail: newEmail,
      currentPassword: currentPassword,
    );
    if (result == EmailChangeRequestResult.verificationSent) {
      final uid = _currentUser?.id;
      if (uid != null) {
        _beginPendingEmailChange(
          originalUid: uid,
          originalEmail: _currentUser?.email ?? '',
          pendingEmail: newEmail.trim(),
          password: currentPassword,
        );
      }
      return true;
    }
    return false;
  }

  Future<bool> isCurrentEmailVerified() {
    return _repository.isCurrentEmailVerified();
  }

  Future<void> requestCurrentEmailVerification() {
    return _repository.requestCurrentEmailVerification();
  }

  Future<User?> refreshAuthenticatedUser() async {
    if (hasPendingEmailChange) {
      await checkPendingEmailChange();
      return _currentUser;
    }

    final refreshed = await _repository.refreshAuthenticatedUser();
    _currentUser = refreshed;
    notifyListeners();
    return _currentUser;
  }

  Future<PendingEmailChangeRecoveryStatus?> checkPendingEmailChange({
    bool manual = false,
  }) async {
    if (_pendingEmailCheckInFlight != null) {
      await _pendingEmailCheckInFlight;
      return _latestPendingEmailStatus(manual: manual);
    }

    if (_pendingEmailChange == null) {
      return null;
    }

    if (_isPendingEmailExpired) {
      _onPendingEmailTimeout();
      return PendingEmailChangeRecoveryStatus.failed;
    }

    final check = _runPendingEmailCheck(manual: manual);
    _pendingEmailCheckInFlight = check;
    try {
      await check;
    } finally {
      if (identical(_pendingEmailCheckInFlight, check)) {
        _pendingEmailCheckInFlight = null;
      }
    }
    return _latestPendingEmailStatus(manual: manual);
  }

  PendingEmailChangeRecoveryStatus? _latestPendingEmailStatus({
    required bool manual,
  }) {
    if (hasPendingEmailChange) {
      return PendingEmailChangeRecoveryStatus.pending;
    }
    if (_pendingEmailRecoveryError != null) {
      return PendingEmailChangeRecoveryStatus.failed;
    }
    if (_pendingEmailChangeSuccessMessage != null || !manual) {
      return PendingEmailChangeRecoveryStatus.completed;
    }
    return null;
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _repository.updatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  void _beginPendingEmailChange({
    required String originalUid,
    required String originalEmail,
    required String pendingEmail,
    required String password,
  }) {
    _clearPendingEmailChange(clearError: true);
    _pendingEmailChange = _PendingEmailChangeState(
      originalUid: originalUid,
      originalEmail: originalEmail,
      pendingEmail: pendingEmail,
      password: password,
      expiresAt: DateTime.now().add(_pendingEmailTimeout),
    );
    _schedulePendingEmailPolling();
    notifyListeners();
    unawaited(checkPendingEmailChange());
  }

  void _schedulePendingEmailPolling() {
    _pendingEmailPollTimer?.cancel();
    _pendingEmailPollTimer = Timer.periodic(_pendingEmailPollInterval, (_) {
      if (_pendingEmailChange == null) {
        _pendingEmailPollTimer?.cancel();
        _pendingEmailPollTimer = null;
        return;
      }
      if (_isPendingEmailExpired) {
        _onPendingEmailTimeout();
        return;
      }
      unawaited(checkPendingEmailChange());
    });
  }

  Future<void> _runPendingEmailCheck({required bool manual}) async {
    if (_checkingPendingEmail || _pendingEmailChange == null) {
      return;
    }

    final pending = _pendingEmailChange!;
    if (_isPendingEmailExpired) {
      _onPendingEmailTimeout();
      return;
    }

    _checkingPendingEmail = true;
    if (!_disposed) {
      notifyListeners();
    }

    try {
      final result = await _repository.checkAndRecoverPendingEmailChange(
        originalUid: pending.originalUid,
        pendingEmail: pending.pendingEmail,
        recoveryPassword: pending.password,
        originalEmail: pending.originalEmail,
      );
      _handlePendingEmailRecoveryResult(result, manual: manual);
    } finally {
      _checkingPendingEmail = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void _handlePendingEmailRecoveryResult(
    PendingEmailChangeRecoveryResult result, {
    required bool manual,
  }) {
    switch (result.status) {
      case PendingEmailChangeRecoveryStatus.pending:
      case PendingEmailChangeRecoveryStatus.transientFailure:
        return;
      case PendingEmailChangeRecoveryStatus.completed:
        final user = result.user;
        if (user == null || user.id != _pendingEmailChange?.originalUid) {
          _failPendingEmailRecovery(
            'Could not verify your account after the email change. '
            'Sign in with your verified email.',
          );
          return;
        }
        _currentUser = user;
        _clearPendingEmailChange(clearError: true);
        if (!manual) {
          _pendingEmailChangeSuccessMessage =
              'Your verified email has been updated.';
        }
        if (!_disposed) {
          notifyListeners();
        }
        return;
      case PendingEmailChangeRecoveryStatus.failed:
        _failPendingEmailRecovery(
          result.message ??
              'Could not restore your session automatically. '
                  'Sign in with your verified email.',
        );
    }
  }

  void _failPendingEmailRecovery(String message) {
    _pendingEmailRecoveryError = message;
    _clearPendingEmailChange(clearError: false);
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onPendingEmailTimeout() {
    _pendingEmailRecoveryError =
        'Email change verification timed out. If you completed verification, '
        'sign in with your new email.';
    _clearPendingEmailChange(clearError: false);
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _clearPendingEmailChange({required bool clearError}) {
    _pendingEmailPollTimer?.cancel();
    _pendingEmailPollTimer = null;
    _pendingEmailChange?.clearPassword();
    _pendingEmailChange = null;
    if (clearError) {
      _pendingEmailRecoveryError = null;
      _pendingEmailChangeSuccessMessage = null;
    }
  }

  void cancelPendingEmailChange() {
    if (_pendingEmailChange == null) return;
    _clearPendingEmailChange(clearError: true);
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clearPendingEmailChange(clearError: true);
    super.dispose();
  }
}
