import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';

class AuthService extends ChangeNotifier {
  AuthService({AuthRepository? repository})
      : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

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

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final user = await _repository.login(
      email: email,
      password: password,
    );
    _currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUser = null;
    await _repository.clearCurrentUser();
    notifyListeners();
  }

  Future<void> updateProfile({
    required String fullName,
    required String email,
    String? profilePicturePath,
  }) async {
    if (_currentUser?.id == null) return;
    _currentUser = await _repository.updateProfile(
      userId: _currentUser!.id!,
      fullName: fullName,
      email: email,
      profilePicturePath: profilePicturePath ?? _currentUser!.profilePicturePath,
    );
    notifyListeners();
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
