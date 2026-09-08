import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/movements.dart';
import '../core/progression/practice_variant.dart';
import '../data/models/movement.dart';
import '../data/models/training_prop.dart';

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
  bool _migrationDirty = false;

  bool get isInitialized => _initialized;
  bool get onboardingComplete =>
      _completedOnboardingVersion >= onboardingVersion;
  bool get firstCameraSetupComplete => _firstCameraSetupComplete;
  bool get firstSessionGuidanceComplete => _firstSessionGuidanceComplete;

  bool hasCompletedLesson(String movement, TrainingProp prop) {
    final key = PracticeVariant(
      movementName: movement,
      trainingProp: prop,
    ).persistenceKey;
    return _completedLessons.contains(key);
  }

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
    _migrationDirty = false;
    if (_userId != null) {
      try {
        final data = await _readAll();
        final account = data[_userId];
        if (account is Map<String, dynamic>) _load(account);
        if (_migrationDirty) {
          await _persist();
          _migrationDirty = false;
        }
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

  Future<bool> completeLesson(String movement, TrainingProp prop) =>
      _update(() {
        _completedLessons.add(
          PracticeVariant(
            movementName: movement,
            trainingProp: prop,
          ).persistenceKey,
        );
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
    return _persist();
  }

  Future<bool> _persist() async {
    if (_userId == null) return false;
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
    final migrated = _migrateCompletedLessons(
      _strings(data['completed_lessons']),
    );
    _completedLessons = migrated.lessons;
    _migrationDirty = migrated.dirty;
    _firstCameraSetupComplete = data['first_camera_setup_complete'] == true;
    _firstSessionGuidanceComplete =
        data['first_session_guidance_complete'] == true;
    _dismissedTips = _strings(data['dismissed_tips']);
  }

  /// Maps legacy movement-only keys to the first/default supported prop.
  static ({Set<String> lessons, bool dirty}) _migrateCompletedLessons(
    Set<String> raw,
  ) {
    final migrated = <String>{};
    var dirty = false;
    for (final entry in raw) {
      final parsed = PracticeVariant.tryParsePersistenceKey(entry);
      if (parsed != null) {
        migrated.add(parsed.persistenceKey);
        if (parsed.persistenceKey != entry) dirty = true;
        continue;
      }
      dirty = true;
      final movement = _movementByName(entry);
      if (movement == null || movement.supportedProps.isEmpty) continue;
      migrated.add(
        PracticeVariant(
          movementName: movement.name,
          trainingProp: movement.supportedProps.first,
        ).persistenceKey,
      );
    }
    if (migrated.length != raw.length) dirty = true;
    if (!dirty) {
      final sortedRaw = raw.toList()..sort();
      final sortedMigrated = migrated.toList()..sort();
      if (!listEquals(sortedRaw, sortedMigrated)) dirty = true;
    }
    return (lessons: migrated, dirty: dirty);
  }

  static Movement? _movementByName(String name) {
    for (final movement in movementCatalog) {
      if (movement.name == name) return movement;
    }
    return null;
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
