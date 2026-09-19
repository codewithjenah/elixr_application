import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A last-known-authoritative progression value for one Firebase account.
///
/// This is an availability cache only. Firestore's leaderboard document
/// remains the sole XP authority, and pending local sessions never update it.
class TraineeProgressionSnapshot {
  const TraineeProgressionSnapshot({
    required this.userId,
    required this.totalXp,
    this.authoritativeSnapshotAt,
  });

  final String userId;
  final int totalXp;
  final DateTime? authoritativeSnapshotAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'uid': userId,
    'total_xp': totalXp,
    if (authoritativeSnapshotAt != null)
      'authoritative_snapshot_at': authoritativeSnapshotAt!
          .toUtc()
          .toIso8601String(),
  };

  static TraineeProgressionSnapshot? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<Object?, Object?>.from(raw);
    final uid = map['uid'];
    final totalXp = map['total_xp'];
    if (uid is! String ||
        uid.trim().isEmpty ||
        totalXp is! int ||
        totalXp < 0) {
      return null;
    }
    final rawTimestamp = map['authoritative_snapshot_at'];
    DateTime? timestamp;
    if (rawTimestamp != null) {
      if (rawTimestamp is! String) return null;
      timestamp = DateTime.tryParse(rawTimestamp)?.toUtc();
      if (timestamp == null) return null;
    }
    return TraineeProgressionSnapshot(
      userId: uid.trim(),
      totalXp: totalXp,
      authoritativeSnapshotAt: timestamp,
    );
  }
}

/// Durable, account-scoped cache of progression confirmed by Firestore.
///
/// Corrupt or unavailable local data is always treated as a cache miss. The
/// file contains neither credentials nor Firebase tokens.
class TraineeProgressionSnapshotStore {
  TraineeProgressionSnapshotStore({Directory? directory})
    : _directoryOverride = directory;

  static const _schemaVersion = 1;

  final Directory? _directoryOverride;
  Future<void> _mutationTail = Future<void>.value();

  Future<void> save(TraineeProgressionSnapshot snapshot) =>
      _runExclusive(() async {
        final all = await _readAll();
        all[snapshot.userId] = snapshot;
        await _writeAll(all);
      });

  Future<TraineeProgressionSnapshot?> load(String firebaseUid) {
    final uid = firebaseUid.trim();
    if (uid.isEmpty) return Future<TraineeProgressionSnapshot?>.value();
    return _runExclusive(() async {
      final snapshot = (await _readAll())[uid];
      return snapshot?.userId == uid ? snapshot : null;
    });
  }

  Future<void> purge(String firebaseUid) {
    final uid = firebaseUid.trim();
    if (uid.isEmpty) return Future<void>.value();
    return _runExclusive(() async {
      final all = await _readAll();
      if (all.remove(uid) != null) await _writeAll(all);
    });
  }

  Future<Directory> _directory() async =>
      _directoryOverride ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}trainee_progression_snapshots',
      );

  Future<File> _file() async => File(
    '${(await _directory()).path}${Platform.pathSeparator}progression.json',
  );

  Future<Map<String, TraineeProgressionSnapshot>> _readAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, TraineeProgressionSnapshot>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['schema_version'] != _schemaVersion) {
        return <String, TraineeProgressionSnapshot>{};
      }
      final accounts = decoded['accounts'];
      if (accounts is! Map) return <String, TraineeProgressionSnapshot>{};
      final snapshots = <String, TraineeProgressionSnapshot>{};
      for (final entry in accounts.entries) {
        if (entry.key is! String) continue;
        final snapshot = TraineeProgressionSnapshot.tryFromJson(entry.value);
        if (snapshot != null && snapshot.userId == entry.key) {
          snapshots[entry.key] = snapshot;
        }
      }
      return snapshots;
    } on FileSystemException catch (_) {
      return <String, TraineeProgressionSnapshot>{};
    } on FormatException catch (_) {
      return <String, TraineeProgressionSnapshot>{};
    }
  }

  Future<void> _writeAll(Map<String, TraineeProgressionSnapshot> all) async {
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
