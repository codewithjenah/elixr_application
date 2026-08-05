import 'package:flutter/foundation.dart';

import '../../../core/constants/movements.dart';
import '../../../services/settings_service.dart';
import 'practice_preferences_draft.dart';

/// Local draft editor for Live Practice setlist, interval, and music.
///
/// Presentation widgets listen to this notifier; hosts own save/discard
/// actions. Persistence goes through [SettingsService.updateLivePracticePreferences].
class PracticePreferencesController extends ChangeNotifier {
  PracticePreferencesController(SettingsService settings)
    : _settings = settings {
    loadFrom(settings);
  }

  SettingsService _settings;
  late PracticePreferencesDraft _original;
  late PracticePreferencesDraft _draft;

  PracticePreferencesDraft get draft => _draft;
  PracticePreferencesDraft get original => _original;

  bool get isDirty => _draft != _original;

  /// At least one catalog movement after filtering, and a positive interval.
  bool get canSave {
    final normalized = normalizeDraft();
    return normalized.movementNames.isNotEmpty &&
        normalized.intervalSeconds > 0;
  }

  void loadFrom(SettingsService settings) {
    _settings = settings;
    final snapshot = _snapshotFromService(settings);
    _original = snapshot;
    _draft = snapshot;
    notifyListeners();
  }

  void toggleMovement(String name, bool selected) {
    final next = List<String>.of(_draft.movementNames);
    if (selected) {
      if (!next.contains(name)) next.add(name);
    } else {
      next.remove(name);
    }
    _draft = _draft.copyWith(movementNames: next);
    notifyListeners();
  }

  void moveMovement(String name, int delta) {
    final next = List<String>.of(_draft.movementNames);
    final index = next.indexOf(name);
    if (index < 0) return;
    final target = index + delta;
    if (target < 0 || target >= next.length) return;
    final entry = next.removeAt(index);
    next.insert(target, entry);
    _draft = _draft.copyWith(movementNames: next);
    notifyListeners();
  }

  void setInterval(int seconds) {
    _draft = _draft.copyWith(intervalSeconds: seconds);
    notifyListeners();
  }

  void setMusicTrackId(String? id) {
    final trimmed = id?.trim();
    _draft = _draft.copyWith(
      musicTrackId: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    notifyListeners();
  }

  /// Filters unknown catalog names, dedupes preserving order, and nulls empty
  /// music ids. Does not throw — validation for save is exposed via [canSave].
  PracticePreferencesDraft normalizeDraft() {
    final validNames = movementCatalog.map((m) => m.name).toSet();
    final seen = <String>{};
    final movements = <String>[];
    for (final name in _draft.movementNames) {
      if (!validNames.contains(name)) continue;
      if (seen.add(name)) movements.add(name);
    }
    final track = _draft.musicTrackId?.trim();
    return PracticePreferencesDraft(
      movementNames: List.unmodifiable(movements),
      intervalSeconds: _draft.intervalSeconds,
      musicTrackId: (track == null || track.isEmpty) ? null : track,
    );
  }

  Future<SettingsWriteOutcome> save() async {
    final normalized = normalizeDraft();
    if (normalized.movementNames.isEmpty || normalized.intervalSeconds <= 0) {
      throw ArgumentError(
        'Live Practice preferences require at least one catalog movement '
        'and a positive interval',
      );
    }

    final outcome = await _settings.updateLivePracticePreferences(
      movementNames: normalized.movementNames,
      intervalSeconds: normalized.intervalSeconds,
      musicTrackId: normalized.musicTrackId,
    );

    switch (outcome) {
      case SettingsWriteOutcome.saved:
        final committed = _snapshotFromService(_settings);
        _original = committed;
        _draft = committed;
        notifyListeners();
      case SettingsWriteOutcome.unchanged:
        final current = _snapshotFromService(_settings);
        _original = current;
        _draft = current;
        notifyListeners();
      case SettingsWriteOutcome.writeFailed:
        // Leave draft and original unchanged.
        break;
    }
    return outcome;
  }

  void discard() {
    _draft = _original;
    notifyListeners();
  }

  static PracticePreferencesDraft _snapshotFromService(
    SettingsService settings,
  ) {
    return PracticePreferencesDraft(
      movementNames: List.unmodifiable(settings.justDanceMovementNames),
      intervalSeconds: settings.justDanceIntervalSeconds,
      musicTrackId: settings.selectedMusicTrackId,
    );
  }
}
