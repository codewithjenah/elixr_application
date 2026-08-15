import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local, account-scoped progress for ELIXR's optional learning support.
/// It deliberately never writes tutorial state to Firestore.
class TutorialProgressService extends ChangeNotifier {
  TutorialProgressService({File? file}) : _fileOverride = file;

  static const onboardingVersion = 2;
  final File? _fileOverride;
  String? _userId;
  bool _initialized = false;
  int _completedOnboardingVersion = 0;
  Set<String> _completedLessons = <String>{};
  bool _firstCameraSetupComplete = false;
  bool _firstSessionGuidanceComplete = false;
  Set<String> _dismissedTips = <String>{};

  bool get isInitialized => _initialized;
  bool get onboardingComplete =>
      _completedOnboardingVersion >= onboardingVersion;
  bool get firstCameraSetupComplete => _firstCameraSetupComplete;
  bool get firstSessionGuidanceComplete => _firstSessionGuidanceComplete;
  bool hasCompletedLesson(String movement) =>
      _completedLessons.contains(movement);
  bool isTipDismissed(String id) => _dismissedTips.contains(id);

  Future<void> setUser(String? userId) async {
    final normalized = userId?.trim();
    if (_userId == normalized && _initialized) return;
    _userId = normalized?.isEmpty == true ? null : normalized;
    _initialized = false;
    _completedOnboardingVersion = 0;
    _completedLessons = <String>{};
    _firstCameraSetupComplete = false;
    _firstSessionGuidanceComplete = false;
    _dismissedTips = <String>{};
    if (_userId != null) {
      try {
        final data = await _readAll();
        final account = data[_userId];
        if (account is Map<String, dynamic>) _load(account);
      } catch (_) {
        // A tutorial write/read failure must never block sign-in or practice.
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> completeOnboarding() => _update(() {
    _completedOnboardingVersion = onboardingVersion;
  });
  Future<bool> completeLesson(String movement) => _update(() {
    _completedLessons.add(movement);
  });
  Future<bool> markCameraSetupComplete() => _update(() {
    _firstCameraSetupComplete = true;
  });
  Future<bool> completeFirstSessionGuidance() => _update(() {
    _firstSessionGuidanceComplete = true;
  });
  Future<bool> dismissTip(String id) => _update(() => _dismissedTips.add(id));
  Future<bool> resetForReplay() => _update(() {
    _completedOnboardingVersion = 0;
  });

  Future<bool> _update(void Function() update) async {
    if (_userId == null) return false;
    update();
    notifyListeners();
    try {
      final data = await _readAll();
      data[_userId!] = {
        'onboarding_version': _completedOnboardingVersion,
        'completed_lessons': _completedLessons.toList()..sort(),
        'first_camera_setup_complete': _firstCameraSetupComplete,
        'first_session_guidance_complete': _firstSessionGuidanceComplete,
        'dismissed_tips': _dismissedTips.toList()..sort(),
      };
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _load(Map<String, dynamic> data) {
    _completedOnboardingVersion = data['onboarding_version'] is int
        ? data['onboarding_version'] as int
        : 0;
    _completedLessons = _strings(data['completed_lessons']);
    _firstCameraSetupComplete = data['first_camera_setup_complete'] == true;
    _firstSessionGuidanceComplete =
        data['first_session_guidance_complete'] == true;
    _dismissedTips = _strings(data['dismissed_tips']);
  }

  Set<String> _strings(Object? raw) => raw is List
      ? raw
            .whereType<String>()
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
      : <String>{};

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return <String, dynamic>{};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  Future<File> _file() async =>
      _fileOverride ??
      File(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}tutorial_progress.json',
      );
}
