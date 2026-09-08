import 'package:flutter/foundation.dart';

import '../../../core/progression/practice_variant.dart';
import '../../../core/progression/progression_catalog.dart';
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

  /// At least one catalog-resolvable variant after filtering, and a positive interval.
  bool get canSave {
    final normalized = normalizeDraft();
    return normalized.practiceVariants.isNotEmpty &&
        normalized.intervalSeconds > 0;
  }

  void loadFrom(SettingsService settings) {
    _settings = settings;
    final snapshot = _snapshotFromService(settings);
    _original = snapshot;
    _draft = snapshot;
    notifyListeners();
  }

  void toggleVariant(PracticeVariant variant, bool selected) {
    final next = List<PracticeVariant>.of(_draft.practiceVariants);
    final index = next.indexWhere(
      (entry) => entry.persistenceKey == variant.persistenceKey,
    );
    if (selected) {
      if (index < 0) next.add(variant);
    } else if (index >= 0) {
      next.removeAt(index);
    }
    _draft = _draft.copyWith(practiceVariants: next);
    notifyListeners();
  }

  void moveVariant(PracticeVariant variant, int delta) {
    final next = List<PracticeVariant>.of(_draft.practiceVariants);
    final index = next.indexWhere(
      (entry) => entry.persistenceKey == variant.persistenceKey,
    );
    if (index < 0) return;
    final target = index + delta;
    if (target < 0 || target >= next.length) return;
    final entry = next.removeAt(index);
    next.insert(target, entry);
    _draft = _draft.copyWith(practiceVariants: next);
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

  /// Filters unknown/unsupported variants, dedupes preserving order, and nulls
  /// empty music ids. Does not throw — validation for save is via [canSave].
  PracticePreferencesDraft normalizeDraft() {
    final seen = <String>{};
    final variants = <PracticeVariant>[];
    for (final variant in _draft.practiceVariants) {
      if (resolvePracticeVariant(variant) == null) continue;
      if (seen.add(variant.persistenceKey)) variants.add(variant);
    }
    final track = _draft.musicTrackId?.trim();
    return PracticePreferencesDraft(
      practiceVariants: List.unmodifiable(variants),
      intervalSeconds: _draft.intervalSeconds,
      musicTrackId: (track == null || track.isEmpty) ? null : track,
    );
  }

  Future<SettingsWriteOutcome> save() async {
    final normalized = normalizeDraft();
    if (normalized.practiceVariants.isEmpty ||
        normalized.intervalSeconds <= 0) {
      throw ArgumentError(
        'Live Practice preferences require at least one catalog variant '
        'and a positive interval',
      );
    }

    final outcome = await _settings.updateLivePracticePreferences(
      practiceVariants: normalized.practiceVariants,
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
      practiceVariants: List.unmodifiable(settings.justDancePracticeVariants),
      intervalSeconds: settings.justDanceIntervalSeconds,
      musicTrackId: settings.selectedMusicTrackId,
    );
  }
}
