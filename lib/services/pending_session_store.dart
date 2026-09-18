import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../data/models/class_challenge_session_context.dart';
import '../data/models/practice_feedback.dart';
import '../data/models/rubric_assessment.dart';
import '../data/models/session_assignment_context.dart';
import '../data/models/training_prop.dart';

/// An immutable, account-scoped command for replaying one official session.
///
/// This is intentionally a DTO for [SessionService.saveCompletedSession], not
/// a second Firestore serializer. Firebase remains the only authoritative
/// session writer.
class PendingSession {
  const PendingSession({
    required this.sessionId,
    required this.userId,
    required this.displayName,
    required this.movementName,
    required this.difficulty,
    required this.prop,
    required this.rubric,
    required this.durationSeconds,
    required this.improvements,
    required this.completedAt,
    this.profilePictureUrl,
    this.assignmentContext,
    this.challengeContext,
    this.evidenceFileName,
    this.evidenceSizeBytes,
  });

  static const schemaVersion = 1;

  final String sessionId;
  final String userId;
  final String displayName;
  final String movementName;
  final String difficulty;
  final TrainingProp prop;
  final RubricAssessment rubric;
  final int durationSeconds;
  final List<PracticeFeedback> improvements;
  final DateTime completedAt;
  final String? profilePictureUrl;
  final SessionAssignmentContext? assignmentContext;
  final ClassChallengeSessionContext? challengeContext;

  /// A basename only. The store derives the account/session scoped path.
  final String? evidenceFileName;
  final int? evidenceSizeBytes;

  bool get hasEvidence => evidenceFileName != null && evidenceSizeBytes != null;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'session_id': sessionId,
    'user_id': userId,
    'display_name': displayName,
    if (profilePictureUrl != null) 'profile_picture_url': profilePictureUrl,
    'movement_name': movementName,
    'difficulty': difficulty,
    'prop_type': prop.protocolValue,
    'rubric': rubric.toJson(),
    'duration_seconds': durationSeconds,
    'improvements': [
      for (final item in improvements)
        {'message': item.feedback, 'feedback_type': item.feedbackType},
    ],
    'completed_at': completedAt.toUtc().toIso8601String(),
    if (assignmentContext != null)
      'assignment_context': assignmentContext!.toMap(),
    if (challengeContext != null)
      'challenge_context': challengeContext!.toMap(),
    if (evidenceFileName != null) 'evidence_file_name': evidenceFileName,
    if (evidenceSizeBytes != null) 'evidence_size_bytes': evidenceSizeBytes,
  };

  static PendingSession? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['schema_version'] != schemaVersion) return null;
    String? string(String key) {
      final value = map[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final sessionId = string('session_id');
    final userId = string('user_id');
    final displayName = string('display_name');
    final movementName = string('movement_name');
    final difficulty = string('difficulty');
    final prop = TrainingProp.tryParseStrict(map['prop_type']);
    final rubric = RubricAssessment.tryFromJson(map['rubric']);
    final duration = map['duration_seconds'];
    final completedAtRaw = map['completed_at'];
    final completedAt = completedAtRaw is String
        ? DateTime.tryParse(completedAtRaw)?.toLocal()
        : null;
    if (sessionId == null ||
        userId == null ||
        displayName == null ||
        movementName == null ||
        difficulty == null ||
        prop == null ||
        rubric == null ||
        duration is! int ||
        duration < 0 ||
        completedAt == null) {
      return null;
    }
    final improvementsRaw = map['improvements'];
    if (improvementsRaw is! List) return null;
    final improvements = <PracticeFeedback>[];
    for (final rawItem in improvementsRaw) {
      if (rawItem is! Map ||
          rawItem['message'] is! String ||
          rawItem['feedback_type'] is! String) {
        return null;
      }
      improvements.add(
        PracticeFeedback(
          bottleDetected: false,
          movement: movementName,
          feedback: rawItem['message'] as String,
          feedbackType: rawItem['feedback_type'] as String,
          postureStatus: 'unknown',
        ),
      );
    }
    final evidenceFileName = string('evidence_file_name');
    final evidenceSize = map['evidence_size_bytes'];
    if ((evidenceFileName == null) != (evidenceSize == null) ||
        (evidenceSize != null &&
            (evidenceSize is! int ||
                evidenceSize < 1024 ||
                evidenceSize > 256 * 1024))) {
      return null;
    }
    final profilePicture = map['profile_picture_url'];
    return PendingSession(
      sessionId: sessionId,
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePicture is String ? profilePicture : null,
      movementName: movementName,
      difficulty: difficulty,
      prop: prop,
      rubric: rubric,
      durationSeconds: duration,
      improvements: List.unmodifiable(improvements),
      completedAt: completedAt,
      assignmentContext: SessionAssignmentContext.tryFrom(
        map['assignment_context'],
      ),
      challengeContext: ClassChallengeSessionContext.tryFrom(
        map['challenge_context'],
      ),
      evidenceFileName: evidenceFileName,
      evidenceSizeBytes: evidenceSize as int?,
    );
  }
}

class PendingSessionConflictException implements Exception {
  const PendingSessionConflictException(this.sessionId);
  final String sessionId;

  @override
  String toString() => 'Conflicting pending session: $sessionId';
}

class PendingSessionStoreCorruptionException implements Exception {
  const PendingSessionStoreCorruptionException();
}

/// Durable local outbox for completed official attempts.
///
/// The JSON contains only small immutable session commands. Optional evidence
/// stays in an account/session scoped file beside it, never as base64 JSON.
class PendingSessionStore {
  PendingSessionStore({Directory? directory}) : _directoryOverride = directory;

  final Directory? _directoryOverride;
  Future<void> _mutationTail = Future<void>.value();
  bool _hasCorruptData = false;

  Future<List<PendingSession>> listForUser(String userId) async {
    final all = await _readAll();
    return List.unmodifiable(all[userId] ?? const <PendingSession>[]);
  }

  Future<void> enqueue(PendingSession session, {Uint8List? evidenceBytes}) =>
      _runExclusive(() => _enqueue(session, evidenceBytes: evidenceBytes));

  Future<void> _enqueue(
    PendingSession session, {
    Uint8List? evidenceBytes,
  }) async {
    if (session.hasEvidence) {
      if (evidenceBytes == null ||
          evidenceBytes.lengthInBytes != session.evidenceSizeBytes) {
        throw ArgumentError(
          'Pending evidence does not match its immutable metadata.',
        );
      }
    } else if (evidenceBytes != null) {
      throw ArgumentError('Evidence bytes require explicit evidence consent.');
    }

    final all = await _readAll();
    if (_hasCorruptData) throw const PendingSessionStoreCorruptionException();
    final existing = all[session.userId] ?? <PendingSession>[];
    final duplicate = existing.where(
      (item) => item.sessionId == session.sessionId,
    );
    if (duplicate.isNotEmpty) {
      if (_sameSnapshot(duplicate.single, session)) return;
      throw PendingSessionConflictException(session.sessionId);
    }

    var createdEvidence = false;
    try {
      if (session.hasEvidence) {
        final evidence = await evidenceFileFor(session);
        await evidence.parent.create(recursive: true);
        await evidence.writeAsBytes(evidenceBytes!, flush: true);
        createdEvidence = true;
      }
      all[session.userId] = [...existing, session];
      await _writeAll(all);
    } catch (_) {
      if (createdEvidence) {
        final evidence = await evidenceFileFor(session);
        if (await evidence.exists()) await evidence.delete();
      }
      rethrow;
    }
  }

  Future<void> remove(PendingSession session) =>
      _runExclusive(() => _remove(session));

  Future<void> _remove(PendingSession session) async {
    // Evidence is deliberately retained until the authoritative remote writer
    // returns successfully. A deletion error leaves the queue item intact for
    // a safe, idempotent replay rather than silently discarding it.
    final all = await _readAll();
    if (_hasCorruptData) throw const PendingSessionStoreCorruptionException();
    final current = all[session.userId] ?? const <PendingSession>[];
    final next = current
        .where((item) => item.sessionId != session.sessionId)
        .toList();
    if (next.length == current.length) return;
    if (next.isEmpty) {
      all.remove(session.userId);
    } else {
      all[session.userId] = next;
    }
    await _writeAll(all);
    // The remote save is already confirmed when this runs. Commit removal of
    // its replay command first so a crash cannot leave a permanent item that
    // refers to a now-deleted image. A failed local cleanup leaves only an
    // orphaned private file; it is harmless and is purged with the account.
    if (session.hasEvidence) {
      final evidence = await evidenceFileFor(session);
      try {
        if (await evidence.exists()) await evidence.delete();
      } catch (_) {}
    }
  }

  Future<void> purgeUser(String userId) =>
      _runExclusive(() => _purgeUser(userId));

  Future<void> _purgeUser(String userId) async {
    final all = await _readAll();
    if (_hasCorruptData) throw const PendingSessionStoreCorruptionException();
    all.remove(userId);
    await _writeAll(all);
    final directory = await _evidenceDirectoryForUser(userId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<File> evidenceFileFor(PendingSession session) async {
    if (!session.hasEvidence) throw StateError('This session has no evidence.');
    final safeName = '${session.sessionId}.jpg';
    return File(
      '${(await _evidenceDirectoryForUser(session.userId)).path}${Platform.pathSeparator}$safeName',
    );
  }

  Future<Directory> _evidenceDirectoryForUser(String userId) async => Directory(
    '${(await _directory()).path}${Platform.pathSeparator}evidence${Platform.pathSeparator}$userId',
  );

  Future<Directory> _directory() async =>
      _directoryOverride ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}pending_sessions',
      );

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}outbox.json');
  Future<File> _backupFile() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}outbox.backup.json',
  );

  Future<Map<String, List<PendingSession>>> _readAll() async {
    _hasCorruptData = false;
    final file = await _file();
    final backup = await _backupFile();
    for (final candidate in [file, backup]) {
      if (!await candidate.exists()) {
        continue;
      }
      try {
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map ||
            decoded['schema_version'] != 1 ||
            decoded['accounts'] is! Map) {
          _hasCorruptData = true;
          continue;
        }
        final result = <String, List<PendingSession>>{};
        for (final entry in (decoded['accounts'] as Map).entries) {
          if (entry.key is! String || entry.value is! List) {
            _hasCorruptData = true;
            continue;
          }
          final items = <PendingSession>[];
          var valid = true;
          for (final raw in entry.value as List) {
            final session = PendingSession.tryFromJson(raw);
            if (session == null || session.userId != entry.key) {
              valid = false;
              _hasCorruptData = true;
              break;
            }
            items.add(session);
          }
          if (valid) {
            result[entry.key] = items;
          }
        }
        return result;
      } catch (_) {
        // Do not delete a malformed file here. The backup may still contain
        // the last durable version, and corruption must never erase another
        // account's pending work.
        _hasCorruptData = true;
      }
    }
    return <String, List<PendingSession>>{};
  }

  Future<void> _writeAll(Map<String, List<PendingSession>> all) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final file = await _file();
    final backup = await _backupFile();
    final temporary = File('${file.path}.tmp');
    final data = jsonEncode({
      'schema_version': 1,
      'accounts': {
        for (final entry in all.entries)
          entry.key: [for (final session in entry.value) session.toJson()],
      },
    });
    await temporary.writeAsString(data, flush: true);
    if (await file.exists()) await file.copy(backup.path);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    if (await backup.exists()) await backup.delete();
  }

  bool _sameSnapshot(PendingSession a, PendingSession b) =>
      jsonEncode(a.toJson()) == jsonEncode(b.toJson());

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final result = _mutationTail.then((_) => action());
    _mutationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
