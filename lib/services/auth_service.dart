import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/leaderboard_repository.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    AuthRepository? repository,
    LeaderboardRepository? leaderboardRepository,
  }) : _repository = repository ?? AuthRepository(),
       _leaderboardRepository =
           leaderboardRepository ?? LeaderboardRepository();

  final AuthRepository _repository;
  final LeaderboardRepository _leaderboardRepository;

  User? _currentUser;
  bool _isLoading = true;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    await fb.FirebaseAuth.instance.authStateChanges().first;
    _currentUser = await _repository.loadPersistedUser();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final user = await _repository.register(
      fullName: fullName,
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
    _currentUser = null;
    await _repository.clearCurrentUser();
    notifyListeners();
  }

  Future<void> updateProfileDetails({
    required String fullName,
    String? profilePicturePath,
  }) async {
    if (_currentUser?.id == null) {
      throw Exception('Not authenticated');
    }
    final userId = _currentUser!.id!;
    _currentUser = await _repository.updateProfileDetails(
      userId: userId,
      fullName: fullName,
      profilePicturePath:
          profilePicturePath ?? _currentUser!.profilePicturePath,
    );

    try {
      await _leaderboardRepository.syncDisplayName(
        userId: userId,
        displayName: fullName,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Leaderboard display_name sync failed: userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }

    notifyListeners();
  }

  Future<bool> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    final result = await _repository.requestEmailChange(
      newEmail: newEmail,
      currentPassword: currentPassword,
    );
    return result == EmailChangeRequestResult.verificationSent;
  }

  Future<bool> isCurrentEmailVerified() {
    return _repository.isCurrentEmailVerified();
  }

  Future<void> requestCurrentEmailVerification() {
    return _repository.requestCurrentEmailVerification();
  }

  Future<User?> refreshAuthenticatedUser() async {
    _currentUser = await _repository.refreshAuthenticatedUser();
    notifyListeners();
    return _currentUser;
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
}
