import 'dart:convert';
import 'dart:io';

import 'package:elixr_core/models/user.dart';
import 'package:path_provider/path_provider.dart';

/// The non-secret, account-scoped profile data that permits a previously
/// authenticated Trainee to enter local practice while Firebase is offline.
///
/// This is deliberately not a general [User] serializer. In particular it
/// never contains credentials, Auth tokens, Teacher access codes, or Storage
/// download URLs (which may contain a bearer-like download token).
class TraineeProfileSnapshot {
  const TraineeProfileSnapshot({
    required this.user,
    required this.emailVerified,
  });

  final User user;
  final bool emailVerified;

  String get userId => user.id!.trim();

  static TraineeProfileSnapshot? fromAuthoritativeUser(
    User user, {
    required bool emailVerified,
  }) {
    final userId = user.id?.trim();
    if (userId == null || userId.isEmpty || !user.isTrainee) return null;
    return TraineeProfileSnapshot(
      user: User(
        id: userId,
        firstName: user.firstName,
        middleName: user.middleName,
        lastName: user.lastName,
        email: user.email,
        role: User.roleTrainee,
        sessionEvidenceEnabled: user.sessionEvidenceEnabled,
      ),
      emailVerified: emailVerified,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'uid': userId,
    'role': User.roleTrainee,
    'first_name': user.firstName,
    if (user.middleName?.trim().isNotEmpty == true)
      'middle_name': user.middleName,
    'last_name': user.lastName,
    'email': user.email,
    'email_verified': emailVerified,
    if (user.sessionEvidenceEnabled != null)
      'session_evidence_enabled': user.sessionEvidenceEnabled,
  };

  static TraineeProfileSnapshot? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<Object?, Object?>.from(raw);
    String? requiredString(String name) {
      final value = map[name];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final uid = requiredString('uid');
    final role = requiredString('role');
    final firstName = requiredString('first_name');
    final lastName = requiredString('last_name');
    final email = requiredString('email');
    final emailVerified = map['email_verified'];
    if (uid == null ||
        role != User.roleTrainee ||
        firstName == null ||
        lastName == null ||
        email == null ||
        emailVerified is! bool) {
      return null;
    }
    final middleName = map['middle_name'];
    final evidenceEnabled = map['session_evidence_enabled'];
    if (middleName != null && middleName is! String) return null;
    if (evidenceEnabled != null && evidenceEnabled is! bool) return null;
    return TraineeProfileSnapshot(
      user: User(
        id: uid,
        firstName: firstName,
        middleName: middleName is String && middleName.trim().isNotEmpty
            ? middleName.trim()
            : null,
        lastName: lastName,
        email: email,
        role: User.roleTrainee,
        sessionEvidenceEnabled: evidenceEnabled as bool?,
      ),
      emailVerified: emailVerified,
    );
  }
}

/// A small durable cache of only authoritative Trainee profile snapshots.
///
/// Every record is keyed by Firebase UID and is independently validated on
/// read. Corruption is a cache miss, never an alternate authentication path.
class TraineeProfileSnapshotStore {
  TraineeProfileSnapshotStore({Directory? directory})
    : _directoryOverride = directory;

  static const _schemaVersion = 1;

  final Directory? _directoryOverride;
  Future<void> _mutationTail = Future<void>.value();

  Future<void> save(TraineeProfileSnapshot snapshot) => _runExclusive(() async {
    final all = await _readAll();
    all[snapshot.userId] = snapshot;
    await _writeAll(all);
  });

  Future<TraineeProfileSnapshot?> load(String firebaseUid) async {
    final normalizedUid = firebaseUid.trim();
    if (normalizedUid.isEmpty) return null;
    final snapshot = (await _readAll())[normalizedUid];
    if (snapshot == null || snapshot.userId != normalizedUid) return null;
    return snapshot;
  }

  Future<void> purge(String firebaseUid) {
    final normalizedUid = firebaseUid.trim();
    if (normalizedUid.isEmpty) return Future<void>.value();
    return _runExclusive(() async {
      final all = await _readAll();
      if (all.remove(normalizedUid) != null) await _writeAll(all);
    });
  }

  Future<Directory> _directory() async =>
      _directoryOverride ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}trainee_profile_snapshots',
      );

  Future<File> _file() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}profiles.json',
  );

  Future<Map<String, TraineeProfileSnapshot>> _readAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, TraineeProfileSnapshot>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['schema_version'] != _schemaVersion) {
        return <String, TraineeProfileSnapshot>{};
      }
      final accounts = decoded['accounts'];
      if (accounts is! Map) return <String, TraineeProfileSnapshot>{};
      final snapshots = <String, TraineeProfileSnapshot>{};
      for (final entry in accounts.entries) {
        if (entry.key is! String) continue;
        final snapshot = TraineeProfileSnapshot.tryFromJson(entry.value);
        if (snapshot != null && snapshot.userId == entry.key) {
          snapshots[entry.key] = snapshot;
        }
      }
      return snapshots;
    } on FileSystemException catch (_) {
      return <String, TraineeProfileSnapshot>{};
    } on FormatException catch (_) {
      return <String, TraineeProfileSnapshot>{};
    }
  }

  Future<void> _writeAll(Map<String, TraineeProfileSnapshot> all) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final file = await _file();
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'schema_version': _schemaVersion,
        'accounts': <String, Object?>{
          for (final entry in all.entries) entry.key: entry.value.toJson(),
        },
      }),
      flush: true,
    );
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final result = _mutationTail.then((_) => action());
    _mutationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
