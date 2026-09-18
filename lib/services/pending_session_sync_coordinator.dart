import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pending_session_store.dart';
import 'session_service.dart';

/// Replays locally durable sessions through the single authoritative writer.
///
/// It deliberately has no Firestore payload construction or projection logic:
/// [SessionService] remains responsible for the atomic save, idempotent XP,
/// and best-effort public profile projection after an acknowledged commit.
class PendingSessionSyncCoordinator extends ChangeNotifier {
  PendingSessionSyncCoordinator({
    required PendingSessionStore store,
    required SessionService sessionService,
  }) : _store = store,
       _sessionService = sessionService;

  final PendingSessionStore _store;
  final SessionService _sessionService;
  final Map<String, Future<bool>> _inFlightBySession = {};
  final Set<String> _blockedUserIds = <String>{};
  String? _activeTraineeId;
  bool _disposed = false;

  Future<void> enqueue(PendingSession session, {Uint8List? evidenceBytes}) =>
      _store.enqueue(session, evidenceBytes: evidenceBytes);

  /// Starts a best-effort replay for this exact attempt. A network/Firebase
  /// failure is intentionally represented as false and leaves the item on
  /// disk. An unresolved Firebase Future is never awaited by the completion
  /// UI; it only occupies this session's single-flight slot until app exit.
  Future<bool> syncSession(PendingSession session) {
    if (_activeTraineeId != session.userId ||
        _blockedUserIds.contains(session.userId)) {
      return Future<bool>.value(false);
    }
    final existing = _inFlightBySession[session.sessionId];
    if (existing != null) return existing;

    late final Future<bool> operation;
    operation = _saveAndRemove(session).whenComplete(() {
      if (identical(_inFlightBySession[session.sessionId], operation)) {
        _inFlightBySession.remove(session.sessionId);
      }
    });
    _inFlightBySession[session.sessionId] = operation;
    return operation;
  }

  /// Called from the authenticated account provider and on foreground resume.
  /// Never reads or syncs an account that is not the active Trainee.
  void setActiveTrainee(String? userId) {
    final normalized = userId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_activeTraineeId == next) return;
    _activeTraineeId = next;
    if (next != null) unawaited(syncPendingForActiveTrainee());
  }

  Future<void> syncPendingForActiveTrainee() async {
    final userId = _activeTraineeId;
    if (userId == null) return;
    final pending = await _store.listForUser(userId);
    for (final session in pending) {
      if (_activeTraineeId != userId) return;
      // Sequential replay protects the bounded local runtime and avoids a
      // burst of duplicate network work after a long offline period.
      await syncSession(session);
    }
  }

  Future<bool> _saveAndRemove(PendingSession session) async {
    try {
      Uint8List? evidence;
      if (session.hasEvidence) {
        final file = await _store.evidenceFileFor(session);
        if (!await file.exists()) return false;
        evidence = await file.readAsBytes();
        if (evidence.lengthInBytes != session.evidenceSizeBytes) return false;
      }
      if (_activeTraineeId != session.userId ||
          _blockedUserIds.contains(session.userId)) {
        return false;
      }
      await _sessionService.saveCompletedSession(
        existingSessionId: session.sessionId,
        userId: session.userId,
        displayName: session.displayName,
        profilePictureUrl: session.profilePictureUrl,
        movementName: session.movementName,
        difficulty: session.difficulty,
        prop: session.prop,
        rubric: session.rubric,
        durationSeconds: session.durationSeconds,
        sessionImprovements: session.improvements,
        evidenceJpegBytes: evidence,
        saveEvidence: session.hasEvidence,
        assignmentContext: session.assignmentContext,
        challengeContext: session.challengeContext,
      );
      if (_activeTraineeId != session.userId ||
          _blockedUserIds.contains(session.userId)) {
        return false;
      }
      await _store.remove(session);
      if (!_disposed) notifyListeners();
      return true;
    } catch (_) {
      // Keep every local record on any remote/temporary-evidence failure. The
      // next lifecycle/account activation can replay the same stable ID.
      return false;
    }
  }

  Future<void> purgeAccount(String userId) async {
    // Stop new replay before waiting for any command that was already
    // dispatched. Account deletion is online-only, so an in-flight Firebase
    // operation should resolve (success or auth failure) rather than leaving
    // a competing writer behind while local evidence is purged.
    _blockedUserIds.add(userId);
    final queued = await _store.listForUser(userId);
    await Future.wait(
      queued
          .map((session) => _inFlightBySession[session.sessionId])
          .whereType<Future<bool>>(),
    );
    await _store.purgeUser(userId);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
