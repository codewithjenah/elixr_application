import 'package:flutter/foundation.dart';

import '../../data/models/practice_feedback.dart';

/// Immutable snapshot of the pre-practice readiness gate state.
///
/// Owned and mutated (via [copyWith]) only by [PracticeRunController].
/// The UI reads this via [PracticeRunController.readiness].
@immutable
class PracticeReadinessState {
  const PracticeReadinessState({
    this.items = const [],
    this.complete = false,
    this.stable = false,
    this.stableProgress = 0.0,
    this.frozenSnapshot,
    this.confirming = false,
    this.confirmed = false,
    this.streamStale = false,
    this.recoverableMessage,
  });

  /// Canonical empty state returned before any readiness feedback arrives.
  static const empty = PracticeReadinessState();

  /// Live checklist items from the most recent backend feedback frame.
  final List<ReadinessItemView> items;

  /// True when every item has transitioned to [ReadinessItemStatus.ready].
  final bool complete;

  /// True when all items have been ready long enough to proceed (backend stable timer).
  final bool stable;

  /// Progress toward the stable-readiness threshold (0.0–1.0, clamped).
  final double stableProgress;

  /// Frozen snapshot captured when auto-start confirmed readiness and the
  /// backend accepted [confirm_readiness]. Non-null only during countdown.
  final List<ReadinessItemView>? frozenSnapshot;

  /// True while a [confirm_readiness] command is awaiting a backend ack.
  final bool confirming;

  /// True after the backend accepted [confirm_readiness].
  final bool confirmed;

  /// True when the backend stream has not delivered a fresh readiness frame
  /// within the freshness watchdog window (2 s). Blocks auto-start.
  final bool streamStale;

  /// Recoverable inline message set by a soft rejection (readiness_not_stable,
  /// readiness_stale) or watchdog expiry. Cleared on the next fresh frame.
  final String? recoverableMessage;

  // ── Computed helpers ──────────────────────────────────────────────────────

  /// Items to display: frozen snapshot while waiting for countdown, otherwise live items.
  List<ReadinessItemView> get displayItems => frozenSnapshot ?? items;

  /// True once [frozenSnapshot] has been captured (confirm accepted, in countdown).
  bool get frozen => frozenSnapshot != null;

  /// True when guided practice may auto-start after the Ready beat.
  ///
  /// Requires stable readiness, no in-flight or completed confirmation, and a
  /// fresh backend stream.
  bool get canStartPractice =>
      stable && !confirming && !confirmed && !streamStale;

  /// Number of items currently in [ReadinessItemStatus.ready] state.
  int get readyCount =>
      items.where((i) => i.status == ReadinessItemStatus.ready).length;

  /// Total number of items.
  int get totalCount => items.length;

  // ── copyWith ──────────────────────────────────────────────────────────────

  PracticeReadinessState copyWith({
    List<ReadinessItemView>? items,
    bool? complete,
    bool? stable,
    double? stableProgress,
    List<ReadinessItemView>? frozenSnapshot,
    bool clearFrozen = false,
    bool? confirming,
    bool? confirmed,
    bool? streamStale,
    String? recoverableMessage,
    bool clearRecoverable = false,
  }) {
    return PracticeReadinessState(
      items: items ?? this.items,
      complete: complete ?? this.complete,
      stable: stable ?? this.stable,
      stableProgress: stableProgress ?? this.stableProgress,
      frozenSnapshot: clearFrozen
          ? null
          : (frozenSnapshot ?? this.frozenSnapshot),
      confirming: confirming ?? this.confirming,
      confirmed: confirmed ?? this.confirmed,
      streamStale: streamStale ?? this.streamStale,
      recoverableMessage: clearRecoverable
          ? null
          : (recoverableMessage ?? this.recoverableMessage),
    );
  }

  // ── Equality ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PracticeReadinessState) return false;
    return complete == other.complete &&
        stable == other.stable &&
        stableProgress == other.stableProgress &&
        confirming == other.confirming &&
        confirmed == other.confirmed &&
        streamStale == other.streamStale &&
        recoverableMessage == other.recoverableMessage &&
        listEquals(items, other.items) &&
        listEquals(frozenSnapshot, other.frozenSnapshot);
  }

  @override
  int get hashCode => Object.hash(
    complete,
    stable,
    stableProgress,
    confirming,
    confirmed,
    streamStale,
    recoverableMessage,
    Object.hashAll(items),
    frozenSnapshot == null ? null : Object.hashAll(frozenSnapshot!),
  );

  @override
  String toString() =>
      'PracticeReadinessState('
      'stable: $stable, '
      'complete: $complete, '
      'progress: ${stableProgress.toStringAsFixed(2)}, '
      'items: ${items.length}, '
      'frozen: $frozen, '
      'confirming: $confirming, '
      'confirmed: $confirmed, '
      'streamStale: $streamStale'
      ')';
}
